package AWSUtils::Tasks;
use strict;
use warnings;
use utf8;
use AWSUtils::Exec;
use MT::PluginData;
use Data::Dumper;
use AWSUtils::Utils qw/create_config/;

sub ec2describesnapshots {
    my $plugin = MT->component('AWSUtils');
    my $config = create_config();

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
    my @lists;

    for my $snapshot (@{$res->{Snapshots}}) {
        push @lists, +{
            StartTime => $snapshot->{StartTime} || undef,
            SnapshotId => $snapshot->{'SnapshotId'} || undef,
        };
    }
    $data->data(\@lists);
    $data->save;

    return;   
}

1;

