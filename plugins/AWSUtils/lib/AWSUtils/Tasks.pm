package AWSUtils::Tasks;
use strict;
use warnings;
use utf8;
use AWSUtils::Exec;
use MT::PluginData;
use AWSUtils::Utils qw/create_config/;

sub ec2describesnapshots {
    my $config = create_config();

    return unless $config->{ec2_volume_id};

    my $term = {
        plugin => 'AWSUtils',
        key    => 'describe_snapshots'
    };

    my $data;

    unless ($data = MT::PluginData->load($term)) {
        $data = MT::PluginData->new;
        $data->plugin('AWSUtils');
        $data->key('describe_snapshots');
    }

    my $aws = AWSUtils::Exec->new;

    my $res = $aws->describe_snapshots();

    unless ($res && ref($res) eq 'HASH' && $res->{Snapshots}) {
        MT->log({
            message  => 'AWSUtils: Failed to describe snapshots: '
                        . ($AWS::CLIWrapper::Error->{Message} || 'Unknown error'),
            level    => MT::Log::ERROR(),
            class    => 'system',
            category => 'AWSUtils',
        });
        return;
    }

    my @lists;
    for my $snapshot (@{$res->{Snapshots}}) {
        push @lists, +{
            StartTime  => $snapshot->{StartTime}  || undef,
            SnapshotId => $snapshot->{SnapshotId}  || undef,
        };
    }
    $data->data(\@lists);
    $data->save;

    return;
}

1;
