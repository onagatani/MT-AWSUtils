package AWSUtils::Utils;
use strict;
use warnings;
use utf8;
use parent qw(Exporter);
use Module::Functions;

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
    
    return _overwrite_hash($system_config, $merge_config);
}

sub _overwrite_hash {
    my ($old, $new) = @_;

    my %hash_old = %$old;
    my %hash_new = %$new;

    for my $key (keys %hash_new) {
        if (exists $hash_new{$key} && defined $hash_new{$key}) {
            $hash_old{$key} = $hash_new{$key};
        }
    }
    return \%hash_old;
}

1;

