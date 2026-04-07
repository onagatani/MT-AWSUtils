#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

use MockMT;
use JSON 2;

###############################################################################
# Mock AWSUtils::Exec for Worker testing
###############################################################################
{
    package MockExecForWorker;
    use strict;
    use warnings;

    my @_calls;
    my %_results;

    sub new {
        my ($class, %args) = @_;
        push @_calls, { method => 'new', args => \%args };
        return bless \%args, $class;
    }

    sub s3_sync {
        my ($self, $opt) = @_;
        push @_calls, { method => 's3_sync', opt => $opt };
        return $_results{s3_sync};
    }

    sub cloudfront_invalidation {
        my ($self, $opt) = @_;
        push @_calls, { method => 'cloudfront_invalidation', opt => $opt };
        return $_results{cloudfront_invalidation};
    }

    sub create_snapshot {
        my ($self) = @_;
        push @_calls, { method => 'create_snapshot' };
        return $_results{create_snapshot};
    }

    sub _set_result  { $_results{$_[1]} = $_[2] }
    sub _get_calls   { @_calls }
    sub _clear_calls { @_calls = () }
    sub _reset       { @_calls = (); %_results = (); }
}

# Patch AWSUtils::Exec before loading Worker
BEGIN {
    $INC{'AWSUtils/Exec.pm'} = 1;
    no strict 'refs';
    *{'AWSUtils::Exec::new'} = sub {
        shift; # class
        return MockExecForWorker->new(@_);
    };
}

use AWSUtils::Worker;

###############################################################################
# Class method tests
###############################################################################
subtest 'class methods' => sub {
    is(AWSUtils::Worker->grab_for, 600, 'grab_for is 600 seconds');
    is(AWSUtils::Worker->max_retries, 3, 'max_retries is 3');
    is(AWSUtils::Worker->retry_delay, 60, 'retry_delay is 60 seconds');
};

###############################################################################
# Helper to create a job
###############################################################################
sub make_job {
    my (%args) = @_;
    my $job = TheSchwartz::Job->new();
    $job->funcname('AWSUtils::Worker');
    $job->arg($args{arg});
    $job->coalesce($args{coalesce});
    $job->uniqkey($args{uniqkey} || 'test-key');
    return $job;
}

###############################################################################
# S3 sync job tests
###############################################################################
subtest 'S3 sync job' => sub {

    subtest 'successful sync' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $blog = MockBlog->new(id => 10, site_path => '/var/www/blog10', parent => undef);
        MockBlog->_register($blog);

        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:10', {
            s3_bucket    => 'test-bucket',
            s3_dest_path => '/site',
        });

        MockExecForWorker->_set_result('s3_sync', { status => 'ok' });

        my $job = make_job(
            arg      => { blog_id => 10, task => 'sync' },
            coalesce => 's3',
        );

        AWSUtils::Worker->work($job);

        ok($job->is_completed, 'job marked completed');
        ok(!$job->failure_msg, 'no failure');

        my @logs = MT->_get_logs();
        ok(scalar @logs >= 1, 'log entry created');
        like($logs[0]->{message}, qr/Result of AWS CLI/, 'success message logged');
        is($logs[0]->{level}, MT::Log::INFO(), 'level is INFO');
        is($logs[0]->{blog_id}, 10, 'blog_id in log');
        is($logs[0]->{class}, 'blog', 'class is blog');
    };

    subtest 'sync skips when no blog' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $job = make_job(
            arg      => { blog_id => 0, task => 'sync' },
            coalesce => 's3',
        );

        AWSUtils::Worker->work($job);

        ok(!$job->is_completed, 'job not completed (skipped)');
        my @exec_calls = grep { $_->{method} eq 's3_sync' } MockExecForWorker->_get_calls();
        is(scalar @exec_calls, 0, 'no s3_sync call made');
    };

    subtest 'sync with cloudfront invalidation' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $blog = MockBlog->new(id => 20, site_path => '/var/www/blog20', parent => undef);
        MockBlog->_register($blog);

        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:20', {
            s3_bucket            => 'test-bucket',
            cf_dist_id           => 'E123456',
            cf_invalidation_path => '/*',
        });

        MockExecForWorker->_set_result('s3_sync', { s3 => 'ok' });
        MockExecForWorker->_set_result('cloudfront_invalidation', { cf => 'ok' });

        my $job = make_job(
            arg      => { blog_id => 20, task => 'sync' },
            coalesce => 's3',
        );

        AWSUtils::Worker->work($job);

        ok($job->is_completed, 'job completed');

        my @cf_calls = grep { $_->{method} eq 'cloudfront_invalidation' } MockExecForWorker->_get_calls();
        is(scalar @cf_calls, 1, 'cloudfront invalidation called');
    };

    subtest 'sync without cloudfront when cf_dist_id absent' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $blog = MockBlog->new(id => 30, site_path => '/var/www/blog30', parent => undef);
        MockBlog->_register($blog);

        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:30', {
            s3_bucket => 'test-bucket',
            # no cf_dist_id
        });

        MockExecForWorker->_set_result('s3_sync', { s3 => 'ok' });

        my $job = make_job(
            arg      => { blog_id => 30, task => 'sync' },
            coalesce => 's3',
        );

        AWSUtils::Worker->work($job);

        my @cf_calls = grep { $_->{method} eq 'cloudfront_invalidation' } MockExecForWorker->_get_calls();
        is(scalar @cf_calls, 0, 'no cloudfront call when cf_dist_id absent');
    };

    subtest 'sync failure logs error' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $blog = MockBlog->new(id => 10, site_path => '/var/www/blog10', parent => undef);
        MockBlog->_register($blog);
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:10', { s3_bucket => 'bucket' });

        MockExecForWorker->_set_result('s3_sync', undef);  # failure
        $AWS::CLIWrapper::Error = { Message => 'NoSuchBucket', Code => '404' };

        my $job = make_job(
            arg      => { blog_id => 10, task => 'sync' },
            coalesce => 's3',
        );

        AWSUtils::Worker->work($job);

        ok(!$job->is_completed, 'job not completed');
        ok($job->failure_msg, 'job marked failed');
        like($job->failure_msg, qr/NoSuchBucket/, 'error message in failure');

        my @logs = MT->_get_logs();
        is($logs[0]->{level}, MT::Log::ERROR(), 'level is ERROR');
        like($logs[0]->{message}, qr/NoSuchBucket/, 'error in log');
    };
};

###############################################################################
# CloudFront invalidation job tests
###############################################################################
subtest 'CloudFront invalidation job' => sub {

    subtest 'successful invalidation' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        my $blog = MockBlog->new(id => 10, parent => undef);
        MockBlog->_register($blog);

        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:10', {
            cf_dist_id           => 'E123456',
            cf_invalidation_path => '/images/*',
        });

        MockExecForWorker->_set_result('cloudfront_invalidation', { Id => 'INV-001' });

        my $job = make_job(
            arg      => { blog_id => 10, task => 'create-invalidation' },
            coalesce => 'cloudfront',
        );

        AWSUtils::Worker->work($job);

        ok($job->is_completed, 'job completed');
        my @cf_calls = grep { $_->{method} eq 'cloudfront_invalidation' } MockExecForWorker->_get_calls();
        is(scalar @cf_calls, 1, 'cloudfront invalidation called');
        is($cf_calls[0]->{opt}{cf_dist_id}, 'E123456', 'dist id passed');
    };
};

###############################################################################
# EC2 snapshot job tests
###############################################################################
subtest 'EC2 create-snapshot job' => sub {

    subtest 'successful snapshot' => sub {
        MockMT::setup_default();
        MockExecForWorker->_reset();
        MT->_clear_logs();
        MT::TheSchwartz->_clear_coalesced_jobs();

        MockExecForWorker->_set_result('create_snapshot', { SnapshotId => 'snap-123' });

        my $job = make_job(
            arg      => { blog_id => 0, task => 'create-snapshot' },
            coalesce => 'ec2',
        );

        AWSUtils::Worker->work($job);

        ok($job->is_completed, 'job completed');
        my @ec2_calls = grep { $_->{method} eq 'create_snapshot' } MockExecForWorker->_get_calls();
        is(scalar @ec2_calls, 1, 'create_snapshot called');

        my @logs = MT->_get_logs();
        is($logs[0]->{class}, 'system', 'system class for ec2 (no blog)');
        is($logs[0]->{blog_id}, 0, 'blog_id is 0');
    };
};

###############################################################################
# Unknown service tests
###############################################################################
subtest 'unknown service skipped' => sub {
    MockMT::setup_default();
    MockExecForWorker->_reset();
    MT->_clear_logs();
    MT::TheSchwartz->_clear_coalesced_jobs();

    my $job = make_job(
        arg      => { blog_id => 0, task => 'unknown-task' },
        coalesce => 'unknown_service',
    );

    AWSUtils::Worker->work($job);

    ok(!$job->is_completed, 'job not completed');
    ok(!$job->failure_msg,  'job not failed (just skipped)');
    is(scalar MT->_get_logs(), 0, 'no log entry');
};

###############################################################################
# Job coalescing tests
###############################################################################
subtest 'job coalescing' => sub {
    MockMT::setup_default();
    MockExecForWorker->_reset();
    MT->_clear_logs();

    my $blog = MockBlog->new(id => 10, parent => undef);
    MockBlog->_register($blog);
    my $plugin = MT->component('AWSUtils');
    $plugin->_set_config('blog:10', {
        cf_dist_id           => 'E123',
        cf_invalidation_path => '/*',
    });

    MockExecForWorker->_set_result('cloudfront_invalidation', { ok => 1 });

    my $job1 = make_job(
        arg      => { blog_id => 10, task => 'create-invalidation' },
        coalesce => 'cloudfront',
    );
    my $coalesced_job = make_job(
        arg      => { blog_id => 10, task => 'create-invalidation' },
        coalesce => 'cloudfront',
    );

    # Set up coalesced job to be found
    MT::TheSchwartz->_set_coalesced_jobs($coalesced_job);

    AWSUtils::Worker->work($job1);

    ok($job1->is_completed, 'first job completed');
    ok($coalesced_job->is_completed, 'coalesced job also completed');

    my @cf_calls = grep { $_->{method} eq 'cloudfront_invalidation' } MockExecForWorker->_get_calls();
    is(scalar @cf_calls, 2, 'cloudfront called twice (once per job)');
};

###############################################################################
# Exec receives blog parameter
###############################################################################
subtest 'Exec receives blog parameter' => sub {
    MockMT::setup_default();
    MockExecForWorker->_reset();
    MT->_clear_logs();
    MT::TheSchwartz->_clear_coalesced_jobs();

    my $blog = MockBlog->new(id => 10, site_path => '/var/www/blog10', parent => undef);
    MockBlog->_register($blog);
    my $plugin = MT->component('AWSUtils');
    $plugin->_set_config('blog:10', { s3_bucket => 'bucket' });

    MockExecForWorker->_set_result('s3_sync', { ok => 1 });

    my $job = make_job(
        arg      => { blog_id => 10, task => 'sync' },
        coalesce => 's3',
    );

    AWSUtils::Worker->work($job);

    my @new_calls = grep { $_->{method} eq 'new' } MockExecForWorker->_get_calls();
    ok(scalar @new_calls >= 1, 'Exec->new called');
    is($new_calls[0]->{args}{blog}->id, 10, 'blog passed to Exec constructor');
};

done_testing();
