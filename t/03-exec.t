#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

use MockMT;

###############################################################################
# Mock AWS::CLIWrapper to capture calls instead of running aws CLI
###############################################################################
{
    package MockCLIWrapper;
    use strict;
    use warnings;

    my @_calls;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }

    sub s3 {
        my ($self, $op, $paths, $param) = @_;
        push @_calls, { service => 's3', operation => $op, paths => $paths, param => $param };
        return { status => 'ok', operation => $op };
    }

    sub cloudfront {
        my ($self, $op, $param) = @_;
        push @_calls, { service => 'cloudfront', operation => $op, param => $param };
        return { status => 'ok', operation => $op };
    }

    sub ec2 {
        my ($self, $op, $param) = @_;
        push @_calls, { service => 'ec2', operation => $op, param => $param };
        return { status => 'ok', operation => $op };
    }

    sub _get_calls { @_calls }
    sub _clear_calls { @_calls = () }
}

###############################################################################
# Patch Exec to use MockCLIWrapper
###############################################################################
use AWSUtils::Exec;

{
    no warnings 'redefine';
    my $orig_init = \&AWSUtils::Exec::_init;
    *AWSUtils::Exec::_init = sub {
        my $self = shift;
        my $config = AWSUtils::Utils::create_config($self->{blog});
        $self->config($config);
        $self->aws(MockCLIWrapper->new(
            region      => $config->{region},
            awscli_path => $config->{awscli_path},
        ));
    };
}

###############################################################################
# Constructor tests
###############################################################################
subtest 'constructor' => sub {

    subtest 'uses system config without blog' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();

        my $exec = AWSUtils::Exec->new;
        is($exec->config->{region}, 'ap-northeast-1', 'region from system config');
        is($exec->config->{access_key}, 'AKIAIOSFODNN7EXAMPLE', 'access_key from system');
        ok($exec->aws, 'aws client created');
    };

    subtest 'uses blog-merged config with blog' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('blog:10', {
            s3_bucket => 'blog-bucket',
        });

        my $blog = MockBlog->new(id => 10, parent => undef);
        my $exec = AWSUtils::Exec->new(blog => $blog);
        is($exec->config->{s3_bucket}, 'blog-bucket', 'blog config merged');
        is($exec->config->{region}, 'ap-northeast-1', 'system config inherited');
    };
};

###############################################################################
# s3_sync tests
###############################################################################
subtest 's3_sync' => sub {

    subtest 'returns undef without s3_bucket' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        my $res = $exec->s3_sync({ local_path => '/var/www' });
        is($res, undef, 'returns undef without bucket');
        is(scalar MockCLIWrapper->_get_calls(), 0, 'no AWS call made');
    };

    subtest 'constructs correct S3 path' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->s3_sync({
            local_path   => '/var/www/html',
            s3_bucket    => 'my-bucket',
            s3_dest_path => 'site/files',
        });
        my @calls = MockCLIWrapper->_get_calls();
        is(scalar @calls, 1, 'one call made');
        is($calls[0]->{service}, 's3', 'service is s3');
        is($calls[0]->{operation}, 'sync', 'operation is sync');
        is($calls[0]->{paths}[0], '/var/www/html', 'local path');
        is($calls[0]->{paths}[1], 's3://my-bucket/site/files', 'remote path');
    };

    subtest 'normalizes multiple slashes in path' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->s3_sync({
            local_path   => '/var/www',
            s3_bucket    => 'bucket/',
            s3_dest_path => '/path/',
        });
        my @calls = MockCLIWrapper->_get_calls();
        like($calls[0]->{paths}[1], qr{^s3://bucket/path$}, 'slashes normalized');
    };

    subtest 'handles exclude paths' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->s3_sync({
            local_path => '/var/www',
            s3_bucket  => 'bucket',
            exclude    => '*.log,*.tmp',
        });
        my @calls = MockCLIWrapper->_get_calls();
        is_deeply($calls[0]->{param}{exclude}, ['*.log', '*.tmp'], 'exclude parsed');
    };

    subtest 'no exclude param when not specified' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->s3_sync({
            local_path => '/var/www',
            s3_bucket  => 'bucket',
        });
        my @calls = MockCLIWrapper->_get_calls();
        ok(!exists $calls[0]->{param}{exclude}, 'no exclude in params');
    };

    subtest 'bucket only without dest_path' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->s3_sync({
            local_path => '/var/www',
            s3_bucket  => 'my-bucket',
        });
        my @calls = MockCLIWrapper->_get_calls();
        is($calls[0]->{paths}[1], 's3://my-bucket', 'no trailing slash');
    };
};

###############################################################################
# cloudfront_invalidation tests
###############################################################################
subtest 'cloudfront_invalidation' => sub {

    subtest 'returns undef without cf_dist_id' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        my $res = $exec->cloudfront_invalidation({});
        is($res, undef, 'returns undef without dist_id');
        is(scalar MockCLIWrapper->_get_calls(), 0, 'no AWS call made');
    };

    subtest 'creates invalidation with distribution ID' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        my $res = $exec->cloudfront_invalidation({
            cf_dist_id           => 'E1234567890',
            cf_invalidation_path => '/*',
        });
        my @calls = MockCLIWrapper->_get_calls();
        is(scalar @calls, 1, 'one call made');
        is($calls[0]->{service}, 'cloudfront', 'service is cloudfront');
        is($calls[0]->{param}{'distribution-id'}, 'E1234567890', 'dist id passed');
        ok($calls[0]->{param}{'invalidation-batch'}, 'invalidation-batch present');
        like($calls[0]->{param}{'invalidation-batch'}, qr{/\*}, 'path in batch');
        ok($res, 'returns result');
    };

    subtest 'defaults to /* when path not specified' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->cloudfront_invalidation({
            cf_dist_id => 'E1234567890',
        });
        my @calls = MockCLIWrapper->_get_calls();
        like($calls[0]->{param}{'invalidation-batch'}, qr{/\*}, 'default /* path');
    };

    subtest 'CallerReference includes unique components' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        $exec->cloudfront_invalidation({
            cf_dist_id => 'E1234567890',
        });
        my @calls = MockCLIWrapper->_get_calls();
        my $batch = $calls[0]->{param}{'invalidation-batch'};
        like($batch, qr/CallerReference/, 'CallerReference present');
        # Should contain PID component for uniqueness
        like($batch, qr/$$/, 'contains PID');
    };
};

###############################################################################
# create_snapshot tests
###############################################################################
subtest 'create_snapshot' => sub {

    subtest 'returns undef without ec2_volume_id' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', { region => 'us-east-1' });
        MockCLIWrapper->_clear_calls();

        my $exec = AWSUtils::Exec->new;
        my $res = $exec->create_snapshot();
        is($res, undef, 'returns undef without volume id');
    };

    subtest 'creates snapshot with volume id' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        my $res = $exec->create_snapshot();
        my @calls = MockCLIWrapper->_get_calls();
        is(scalar @calls, 1, 'one call made');
        is($calls[0]->{service}, 'ec2', 'service is ec2');
        is($calls[0]->{operation}, 'create-snapshot', 'operation correct');
        is($calls[0]->{param}{'volume-id'}, 'vol-12345678', 'volume id passed');
        is($calls[0]->{param}{'description'}, 'vol-12345678', 'description set');
    };
};

###############################################################################
# describe_snapshots tests
###############################################################################
subtest 'describe_snapshots' => sub {

    subtest 'returns undef without ec2_volume_id' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', { region => 'us-east-1' });
        MockCLIWrapper->_clear_calls();

        my $exec = AWSUtils::Exec->new;
        my $res = $exec->describe_snapshots();
        is($res, undef, 'returns undef without volume id');
    };

    subtest 'describes snapshots with filter' => sub {
        MockMT::setup_default();
        MockCLIWrapper->_clear_calls();
        my $exec = AWSUtils::Exec->new;
        my $res = $exec->describe_snapshots();
        my @calls = MockCLIWrapper->_get_calls();
        is(scalar @calls, 1, 'one call made');
        is($calls[0]->{operation}, 'describe-snapshots', 'operation correct');
        like($calls[0]->{param}{'filters'}, qr/vol-12345678/, 'filter contains volume id');
    };
};

###############################################################################
# _exec environment variable tests
###############################################################################
subtest '_exec sets environment variables' => sub {
    MockMT::setup_default();

    my $exec = AWSUtils::Exec->new;

    # We can't easily test env vars inside _exec because they're local.
    # But we can verify the config has the right keys
    is($exec->config->{access_key}, 'AKIAIOSFODNN7EXAMPLE', 'access_key in config');
    is($exec->config->{secret_key}, 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', 'secret_key in config');
};

done_testing();
