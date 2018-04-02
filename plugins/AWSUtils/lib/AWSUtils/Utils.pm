package AWSUtils::Utils;
use strict;
use warnings;
use utf8;
use parent qw(Exporter);
use Module::Functions;
use Data::Dumper;

our @EXPORT = get_public_functions();

sub create_config {
    my $blog = shift;
    my $plugin = MT->component('AWSUtils');

    my $website = $blog->website if $blog && $blog->is_blog;
    my $website_config = +{};
    my $blog_config = +{};

    $blog_config = $plugin->get_config_hash("blog:" . $blog->id) if $blog;

    $website_config = $plugin->get_config_hash("blog:" . $website->id) if $website;

    my $system_config = $plugin->get_config_hash('system');

    my $merge_config = _overwrite_hash($website_config, $blog_config);
    
    my $config = _overwrite_hash($system_config, $merge_config);

    return $config;
}

sub _overwrite_hash {
    my ($hash_old, $hash_new) = @_;

    for my $key (keys %$hash_new) {
        $hash_old->{$key} = $hash_new->{$key} if $hash_new->{$key}
    }
    return $hash_old;
}

1;

