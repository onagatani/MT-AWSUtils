#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

use MockMT;

###############################################################################
# Mock AWSUtils::Exec for Tasks testing
###############################################################################
{
    package MockExecForTasks;
    use strict;
    use warnings;

    my $_describe_result;
    my $_new_called = 0;

    sub new {
        my ($class, %args) = @_;
        $_new_called++;
        return bless \%args, $class;
    }

    sub describe_snapshots {
        my ($self) = @_;
        return $_describe_result;
    }

    sub _set_describe_result { $_describe_result = $_[1] }
    sub _new_called { $_new_called }
    sub _reset { $_new_called = 0; $_describe_result = undef; }
}

# Monkey-patch AWSUtils::Exec
BEGIN {
    $INC{'AWSUtils/Exec.pm'} = 1;
}
{
    no warnings 'redefine';
    *AWSUtils::Exec::new = sub { MockExecForTasks->new(@_[1..$#_]) };
    *AWSUtils::Exec::describe_snapshots = sub { MockExecForTasks->describe_snapshots(@_) };
}

use AWSUtils::Tasks;

###############################################################################
# ec2describesnapshots tests
###############################################################################
subtest 'ec2describesnapshots' => sub {

    subtest 'returns early when no ec2_volume_id configured' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        my $plugin = MT->component('AWSUtils');
        $plugin->_set_config('system', {
            region => 'ap-northeast-1',
            # no ec2_volume_id
        });

        my $result = AWSUtils::Tasks::ec2describesnapshots();
        is($result, undef, 'returns undef');
    };

    subtest 'handles API failure gracefully' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        MT->_clear_logs();

        # Simulate failed API call (returns undef)
        MockExecForTasks->_set_describe_result(undef);

        $AWS::CLIWrapper::Error = { Message => 'Access Denied', Code => '403' };

        my $result = AWSUtils::Tasks::ec2describesnapshots();
        is($result, undef, 'returns undef on failure');

        # Should log an error
        my @logs = MT->_get_logs();
        ok(scalar @logs >= 1, 'error logged');
        like($logs[0]->{message}, qr/Failed to describe snapshots/, 'error message correct');
        is($logs[0]->{level}, MT::Log::ERROR(), 'level is ERROR');
    };

    subtest 'handles non-hash response gracefully' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        MT->_clear_logs();

        # Simulate a string response (no Snapshots key)
        MockExecForTasks->_set_describe_result('success');

        my $result = AWSUtils::Tasks::ec2describesnapshots();
        is($result, undef, 'returns undef for non-hash response');
    };

    subtest 'processes snapshots correctly' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        MT::PluginData->_clear_all();

        MockExecForTasks->_set_describe_result({
            Snapshots => [
                { SnapshotId => 'snap-111', StartTime => '2024-01-01T00:00:00Z' },
                { SnapshotId => 'snap-222', StartTime => '2024-01-02T00:00:00Z' },
            ],
        });

        AWSUtils::Tasks::ec2describesnapshots();

        my $data = MT::PluginData->load({
            plugin => 'AWSUtils',
            key    => 'describe_snapshots',
        });

        ok($data, 'PluginData saved');
        my $lists = $data->data();
        is(ref $lists, 'ARRAY', 'data is arrayref');
        is(scalar @$lists, 2, 'two snapshots');
        is($lists->[0]{SnapshotId}, 'snap-111', 'first snapshot id');
        is($lists->[0]{StartTime}, '2024-01-01T00:00:00Z', 'first snapshot time');
        is($lists->[1]{SnapshotId}, 'snap-222', 'second snapshot id');
    };

    subtest 'updates existing PluginData' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        MT::PluginData->_clear_all();

        # First call
        MockExecForTasks->_set_describe_result({
            Snapshots => [
                { SnapshotId => 'snap-old', StartTime => '2024-01-01T00:00:00Z' },
            ],
        });
        AWSUtils::Tasks::ec2describesnapshots();

        # Second call with new data
        MockExecForTasks->_set_describe_result({
            Snapshots => [
                { SnapshotId => 'snap-new', StartTime => '2024-02-01T00:00:00Z' },
            ],
        });
        AWSUtils::Tasks::ec2describesnapshots();

        my $data = MT::PluginData->load({
            plugin => 'AWSUtils',
            key    => 'describe_snapshots',
        });
        my $lists = $data->data();
        is(scalar @$lists, 1, 'data replaced, not appended');
        is($lists->[0]{SnapshotId}, 'snap-new', 'new snapshot data');
    };

    subtest 'handles empty Snapshots array' => sub {
        MockMT::setup_default();
        MockExecForTasks->_reset();
        MT::PluginData->_clear_all();

        MockExecForTasks->_set_describe_result({
            Snapshots => [],
        });

        AWSUtils::Tasks::ec2describesnapshots();

        my $data = MT::PluginData->load({
            plugin => 'AWSUtils',
            key    => 'describe_snapshots',
        });
        ok($data, 'PluginData saved even for empty list');
        is(scalar @{$data->data()}, 0, 'empty array saved');
    };
};

done_testing();
