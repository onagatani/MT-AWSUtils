#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

use MockMT;

###############################################################################
# Load the plugin file once and get the registered plugin object
###############################################################################
MT->_reset();
my $load_result = do './plugins/AWSUtils/AWSUtils.pl';

# Helper: setup the plugin with default system config
sub _setup_plugin {
    my $p = MT->component('AWSUtils');
    $p->_set_config('system', {
        access_key    => 'AKIAIOSFODNN7EXAMPLE',
        secret_key    => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region        => 'ap-northeast-1',
        awscli_path   => 'aws',
        ec2_volume_id => 'vol-12345678',
    });
    return $p;
}

###############################################################################
# Load test
###############################################################################
subtest 'plugin loads' => sub {
    ok(!$@, 'no compilation error') or diag $@;
    ok(defined $load_result, 'plugin file loaded');
    ok(MT->component('AWSUtils'), 'plugin registered as component');
};

###############################################################################
# _check_perm tests
###############################################################################
subtest '_check_perm' => sub {

    subtest 'returns 0 when instance is not MT::App' => sub {
        MT->_set_instance(bless {}, 'SomeOtherClass');
        is(MT::Plugin::AWSUtils::_check_perm(), 0, 'non-App instance returns 0');
    };

    subtest 'returns 0 when no user' => sub {
        my $app = MT::App->new(user => undef);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_check_perm(), 0, 'no user returns 0');
    };

    subtest 'returns 1 for superuser' => sub {
        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_check_perm(), 1, 'superuser returns 1');
    };

    subtest 'returns 1 for admin permission' => sub {
        my $perm = MockPermission->new(_can_do => { administer => 1 });
        my $author = MockAuthor->new(
            is_superuser => 0,
            _permissions => { 0 => $perm },
        );
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_check_perm(), 1, 'admin permission returns 1');
    };

    subtest 'returns 0 for non-admin user' => sub {
        my $perm = MockPermission->new(_can_do => {});
        my $author = MockAuthor->new(
            is_superuser => 0,
            _permissions => { 0 => $perm },
        );
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_check_perm(), 0, 'non-admin returns 0');
    };

    subtest 'returns 0 when no permissions object' => sub {
        my $author = MockAuthor->new(
            is_superuser => 0,
            _permissions => {},
        );
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_check_perm(), 0, 'no permissions returns 0');
    };
};

###############################################################################
# _validate_request tests
###############################################################################
subtest '_validate_request' => sub {

    subtest 'returns undef (pass) for superuser' => sub {
        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_validate_request($app), undef, 'valid request returns undef');
    };

    subtest 'returns permission_denied for non-admin' => sub {
        my $perm = MockPermission->new(_can_do => {});
        my $author = MockAuthor->new(
            is_superuser => 0,
            _permissions => { 0 => $perm },
        );
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);
        is(MT::Plugin::AWSUtils::_validate_request($app), 'permission_denied', 'returns permission_denied');
    };
};

###############################################################################
# _ec2describe tests
###############################################################################
subtest '_ec2describe' => sub {

    subtest 'returns page with snapshot data' => sub {
        _setup_plugin();
        MT::PluginData->_clear_all();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);

        my $pd = MT::PluginData->new;
        $pd->plugin('AWSUtils');
        $pd->key('describe_snapshots');
        $pd->data([
            { SnapshotId => 'snap-aaa', StartTime => '2024-01-01' },
        ]);
        $pd->save;

        my $result = MT::Plugin::AWSUtils::_ec2describe($app);
        ok($result, 'returns a result');
        is(ref $result, 'HASH', 'result is hashref');
        is(ref $result->{param}{data}, 'ARRAY', 'data is array');
        is($result->{param}{data}[0]{SnapshotId}, 'snap-aaa', 'snapshot data present');
    };

    subtest 'handles no snapshot data' => sub {
        _setup_plugin();
        MT::PluginData->_clear_all();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_ec2describe($app);
        ok($result, 'returns a result');
        ok(!$result->{param}{data}, 'no data when no snapshots');
    };

    subtest 'denied for non-admin' => sub {
        _setup_plugin();
        my $perm = MockPermission->new(_can_do => {});
        my $author = MockAuthor->new(
            is_superuser => 0,
            _permissions => { 0 => $perm },
        );
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_ec2describe($app);
        is($result, 'permission_denied', 'permission denied');
    };
};

###############################################################################
# _ec2snapshot tests
###############################################################################
subtest '_ec2snapshot' => sub {

    subtest 'does not insert job without ec2_volume_id' => sub {
        my $p = MT->component('AWSUtils');
        $p->_set_config('system', {
            region => 'ap-northeast-1',
            # no ec2_volume_id
        });
        MT::TheSchwartz->_clear_inserted_jobs();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_ec2snapshot($app);
        ok($result, 'returns a page');

        my @jobs = MT::TheSchwartz->_get_inserted_jobs();
        is(scalar @jobs, 0, 'no job inserted when ec2_volume_id missing');
    };

    subtest 'inserts job when ec2_volume_id present' => sub {
        _setup_plugin();
        MT::TheSchwartz->_clear_inserted_jobs();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_ec2snapshot($app);
        ok($result, 'returns a page');

        my @jobs = MT::TheSchwartz->_get_inserted_jobs();
        is(scalar @jobs, 1, 'one job inserted');
        is($jobs[0]->arg->{task}, 'create-snapshot', 'task is create-snapshot');
        is($jobs[0]->coalesce, 'ec2', 'coalesce is ec2');
    };
};

###############################################################################
# _invalidation tests
###############################################################################
subtest '_invalidation' => sub {

    subtest 'returns error without blog context' => sub {
        _setup_plugin();
        MT::TheSchwartz->_clear_inserted_jobs();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author, blog => undef);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_invalidation($app);
        is($result, undef, 'returns undef (error)');
        ok($app->{_last_error}, 'error set on app');
    };

    subtest 'inserts cloudfront job with blog' => sub {
        _setup_plugin();
        MT::TheSchwartz->_clear_inserted_jobs();

        my $blog = MockBlog->new(id => 10);
        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author, blog => $blog);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_invalidation($app);
        ok($result, 'returns a page');

        my @jobs = MT::TheSchwartz->_get_inserted_jobs();
        is(scalar @jobs, 1, 'one job inserted');
        is($jobs[0]->arg->{blog_id}, 10, 'blog_id set');
        is($jobs[0]->arg->{task}, 'create-invalidation', 'task correct');
        is($jobs[0]->coalesce, 'cloudfront', 'coalesce is cloudfront');
        like($jobs[0]->uniqkey, qr/CloudFront::Invalidation/, 'uniqkey correct');
    };
};

###############################################################################
# _s3sync tests
###############################################################################
subtest '_s3sync' => sub {

    subtest 'returns error without blog context' => sub {
        _setup_plugin();
        MT::TheSchwartz->_clear_inserted_jobs();

        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author, blog => undef);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_s3sync($app);
        is($result, undef, 'returns undef (error)');
        ok($app->{_last_error}, 'error set on app');
    };

    subtest 'inserts s3 sync job with blog' => sub {
        _setup_plugin();
        MT::TheSchwartz->_clear_inserted_jobs();

        my $blog = MockBlog->new(id => 15);
        my $author = MockAuthor->new(is_superuser => 1);
        my $app = MT::App->new(user => $author, blog => $blog);
        MT->_set_instance($app);

        my $result = MT::Plugin::AWSUtils::_s3sync($app);
        ok($result, 'returns a page');

        my @jobs = MT::TheSchwartz->_get_inserted_jobs();
        is(scalar @jobs, 1, 'one job inserted');
        is($jobs[0]->arg->{blog_id}, 15, 'blog_id set');
        is($jobs[0]->arg->{task}, 'sync', 'task correct');
        is($jobs[0]->coalesce, 's3', 'coalesce is s3');
    };
};

###############################################################################
# Config template tests
###############################################################################
subtest 'system config template' => sub {
    my $html = MT::Plugin::AWSUtils::_system_config();
    like($html, qr/name="access_key"/,   'access_key field');
    like($html, qr/name="secret_key"/,   'secret_key field');
    like($html, qr/type="password"/,     'secret_key is password type');
    like($html, qr/name="region"/,       'region field');
    like($html, qr/name="awscli_path"/,  'awscli_path field');
    like($html, qr/name="ec2_volume_id"/, 'ec2_volume_id field');
    unlike($html, qr/type="text"\s+name="secret_key"/s, 'secret_key is NOT type text');
};

subtest 'blog config template' => sub {
    my $html = MT::Plugin::AWSUtils::_blog_config();
    like($html, qr/name="cf_dist_id"/,           'cf_dist_id field');
    like($html, qr/name="cf_invalidation_path"/, 'cf_invalidation_path field');
    like($html, qr/name="s3_bucket"/,            's3_bucket field');
    like($html, qr/name="s3_dest_path"/,         's3_dest_path field');
};

done_testing();
