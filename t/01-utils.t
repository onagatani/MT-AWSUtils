#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

use MockMT;

###############################################################################
# _overwrite_hash tests
###############################################################################
subtest '_overwrite_hash' => sub {
    MockMT::setup_default();

    # Access private function
    my $ow = \&AWSUtils::Utils::_overwrite_hash;

    require AWSUtils::Utils;

    subtest 'merges new values into old hash' => sub {
        my $old = { a => 1, b => 2 };
        my $new = { b => 3, c => 4 };
        my $result = $ow->($old, $new);
        is($result->{a}, 1, 'keeps old value when no new key');
        is($result->{b}, 3, 'new value overwrites old');
        is($result->{c}, 4, 'adds new key');
    };

    subtest 'skips undef values in new hash' => sub {
        my $old = { a => 1, b => 2 };
        my $new = { a => undef, b => 3 };
        my $result = $ow->($old, $new);
        is($result->{a}, 1, 'undef does not overwrite');
        is($result->{b}, 3, 'defined value overwrites');
    };

    subtest 'skips empty string values in new hash' => sub {
        my $old = { a => 'hello', b => 'world' };
        my $new = { a => '', b => 'new' };
        my $result = $ow->($old, $new);
        is($result->{a}, 'hello', 'empty string does not overwrite');
        is($result->{b}, 'new',   'non-empty string overwrites');
    };

    subtest 'empty old hash gets new values' => sub {
        my $old = {};
        my $new = { x => 10 };
        my $result = $ow->($old, $new);
        is($result->{x}, 10, 'new value added to empty hash');
    };

    subtest 'empty new hash leaves old unchanged' => sub {
        my $old = { x => 10 };
        my $new = {};
        my $result = $ow->($old, $new);
        is($result->{x}, 10, 'old value preserved');
    };

    subtest 'zero value overwrites' => sub {
        my $old = { count => 5 };
        my $new = { count => 0 };
        my $result = $ow->($old, $new);
        # 0 is falsy but defined and not empty string - but our check uses ne ''
        # 0 ne '' is true, so 0 should overwrite
        is($result->{count}, 0, 'zero overwrites existing value');
    };
};

###############################################################################
# create_config tests
###############################################################################
subtest 'create_config' => sub {
    require AWSUtils::Utils;

    subtest 'returns system config when no blog' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', {
            access_key  => 'SYS_KEY',
            secret_key  => 'SYS_SECRET',
            region      => 'us-east-1',
            awscli_path => '/usr/bin/aws',
        });

        my $config = AWSUtils::Utils::create_config();
        is($config->{access_key}, 'SYS_KEY',    'access_key from system');
        is($config->{region},     'us-east-1',  'region from system');
        is($config->{awscli_path}, '/usr/bin/aws', 'awscli_path from system');
    };

    subtest 'merges blog config over system config' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', {
            access_key => 'SYS_KEY',
            region     => 'us-east-1',
            s3_bucket  => 'system-bucket',
        });
        $plugin->_set_config('blog:10', {
            s3_bucket   => 'blog-bucket',
            s3_dest_path => '/blog10',
        });

        my $blog = MockBlog->new(id => 10, parent => undef);
        my $config = AWSUtils::Utils::create_config($blog);
        is($config->{access_key}, 'SYS_KEY',      'access_key falls back to system');
        is($config->{region},     'us-east-1',     'region from system');
        is($config->{s3_bucket},  'blog-bucket',   'blog s3_bucket overrides system');
        is($config->{s3_dest_path}, '/blog10',     'blog-only value present');
    };

    subtest 'merges parent > blog > system config' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', {
            access_key => 'SYS_KEY',
            region     => 'us-east-1',
            s3_bucket  => 'system-bucket',
        });
        $plugin->_set_config('blog:1', {
            s3_bucket    => 'parent-bucket',
            cf_dist_id   => 'PARENT_DIST',
        });
        $plugin->_set_config('blog:10', {
            s3_bucket => 'child-bucket',
        });

        my $parent = MockBlog->new(id => 1);
        my $blog   = MockBlog->new(id => 10, parent => $parent);

        my $config = AWSUtils::Utils::create_config($blog);
        is($config->{access_key}, 'SYS_KEY',       'system access_key');
        is($config->{s3_bucket},  'child-bucket',   'child blog overrides parent');
        is($config->{cf_dist_id}, 'PARENT_DIST',    'parent value inherited');
    };

    subtest 'blog without parent' => sub {
        MockMT::setup_default();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', { region => 'ap-northeast-1' });
        $plugin->_set_config('blog:5', { s3_bucket => 'my-bucket' });

        my $blog = MockBlog->new(id => 5, parent => undef);
        my $config = AWSUtils::Utils::create_config($blog);
        is($config->{region},    'ap-northeast-1', 'system region');
        is($config->{s3_bucket}, 'my-bucket',      'blog bucket');
    };
};

done_testing();
