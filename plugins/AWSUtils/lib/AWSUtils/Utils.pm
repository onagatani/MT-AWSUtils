package AWSUtils::Utils;
use strict;
use warnings;
use utf8;
use parent qw(Exporter);

our @EXPORT_OK = qw(create_config);

sub create_config {
    my $blog = shift;
    my $plugin = MT->component('AWSUtils');

    my $parent;
    if ($blog) {
        # MT7+: use $blog->parent, fallback to $blog->website for older MT
        if ($blog->can('parent')) {
            $parent = $blog->parent;
        } elsif ($blog->can('website') && $blog->can('is_blog') && $blog->is_blog) {
            $parent = $blog->website;
        }
    }

    my $parent_config = +{};
    my $blog_config = +{};

    $blog_config = $plugin->get_config_hash("blog:" . $blog->id) if $blog;
    $parent_config = $plugin->get_config_hash("blog:" . $parent->id) if $parent;

    my $system_config = $plugin->get_config_hash('system');

    my $merge_config = _overwrite_hash($parent_config, $blog_config);

    my $config = _overwrite_hash($system_config, $merge_config);

    return $config;
}

sub _overwrite_hash {
    my ($hash_old, $hash_new) = @_;

    for my $key (keys %$hash_new) {
        $hash_old->{$key} = $hash_new->{$key} if defined $hash_new->{$key} && $hash_new->{$key} ne '';
    }
    return $hash_old;
}

1;
