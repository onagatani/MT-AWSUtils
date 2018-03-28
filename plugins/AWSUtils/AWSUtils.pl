package MT::Plugin::AWSUtils;
use strict;
use warnings;
use base qw( MT::Plugin );
use AWS::CLIWrapper;
use Data::Dumper;
use MT::TheSchwartz;
use TheSchwartz::Job;

our $PLUGIN_NAME = 'AWSUtils';
our $VERSION = '0.1';
our $SCHEMA_VERSION = '0.1';

my $plugin = __PACKAGE__->new({
    name           => $PLUGIN_NAME,
    version        => $VERSION,
    schema_version => $SCHEMA_VERSION,
    key            => $PLUGIN_NAME,
    id             => $PLUGIN_NAME,
    author_name    => 'onagatani',
    author_link    => 'http://blog.onagatani.com/',
    description    => '<__trans phrase="Utility for AWS.">',
    plugin_link    => 'https://github.com/onagatani/MT-AWSUtils',
    registry       => {
        l10n_lexicon => {
            ja => {
                'Utility for AWS.' => 'AWS用のユーティリティープラグイン',
            },
        },
        applications => {
            cms => {
                menus => {
                    'AWSUtils' => {
                        label => 'Utility for AWS',
                        order => 20000,
                    },
                    'AWSUtils:invalidation' => {
                        label             => "CloudFront Invalidation",
                        order             => 200100,
                        mode              => 'invalidation',
                        permission        => 'administer',
                        system_permission => 'administer',
                        condition         => \&_check_perm,
                        view              => [ 'blog', 'website' ],
                    },
                    'AWSUtils:s3sync' => {
                        label             => "S3 Synchronization",
                        order             => 200200,
                        mode              => 's3sync',
                        permission        => 'administer',
                        system_permission => 'administer',
                        condition         => \&_check_perm,
                        view              => [ 'blog', 'website' ],
                    },
                },
                methods => {
                    invalidation => \&_invalidation,
                    s3sync       => \&_s3sync,
                },
            },
        },
        task_workers => {
            awsutils_invalidation => { 
                class => 'AWSUtils::Worker',
                label => 'AWSUtils Worker',
            },
        },
    },
    system_config_template => \&_system_config,
    blog_config_template => \&_blog_config,
    settings => MT::PluginSettings->new([
        ['access_key' ,{ Default => undef , Scope => [qw/system blog/] }],
        ['secret_key' ,{ Default => undef , Scope => [qw/system blog/] }],
        ['region'     ,{ Default => 'ap-northeast-1', Scope => [qw/system blog/] }],
        ['awscli_path',{ Default => 'aws', Scope => 'system' }],
        ['cf_dist_id' ,{ Default => undef , Scope => 'blog' }],
        ['cf_invalidation_path' ,{ Default => '/*' , Scope => 'blog' }],
        ['s3_bucket'  ,{ Default => undef , Scope => 'blog' }],
        ['s3_dest_path' ,{ Default => undef, Scope => 'blog' }],
    ]),
});

MT->add_plugin( $plugin );

sub _check_perm {
    my $app = MT->instance;

    return 0 unless UNIVERSAL::isa( $app , 'MT::App' );
    return 0 unless $app->user;

    my $author = $app->user;
    $author->is_superuser and return 1;

    my $perm;
    if ( $perm = $author->permissions( 0 ) ) {
        $perm->can_administer and return 1;
    }

    return undef;
}

sub _invalidation {
    my $app = shift;

    my $blog = $app->blog or die;

    my $job = TheSchwartz::Job->new();

    $job->funcname( 'AWSUtils::Worker' );
    $job->arg({
       blog_id => $blog->id,
       task    => 'create-invalidation',
    });
    $job->uniqkey($blog->id . "::CloudFront::Invalidation");
    $job->coalesce('cloudfront');
    MT::TheSchwartz->insert($job);

    my $tmpl_name = 'cloudfront_invalidation.tmpl';

    my $tmpl = $plugin->load_tmpl($tmpl_name)
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", $tmpl_name));

    return $app->build_page($tmpl, +{});
}

sub _s3sync {
    my $app = shift;

    my $blog = $app->blog or die;

    my $job = TheSchwartz::Job->new();

    $job->funcname( 'AWSUtils::Worker' );
    $job->arg({
       blog_id => $blog->id,
       task    => 'sync',
    });
    $job->uniqkey($blog->id . "::S3::Sync");
    $job->coalesce('s3');
    MT::TheSchwartz->insert($job);

    my $tmpl_name = 's3sync.tmpl';

    my $tmpl = $plugin->load_tmpl($tmpl_name)
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", $tmpl_name));

    return $app->build_page($tmpl, +{});
}

sub _system_config {
    return <<'__HTML__';
<mtapp:setting
    id="access_key"
    label="<__trans phrase="access_key">">
<input type="text" name="access_key" value="<$mt:getvar name="access_key" escape="html"$>" />
<p class="hint"><__trans phrase="access_key"></p>
</mtapp:setting>
<mtapp:setting
    id="secret_key"
    label="<__trans phrase="secret_key">">
<input type="text" name="secret_key" value="<$mt:getvar name="secret_key" escape="html"$>" />
<p class="hint"><__trans phrase="secret_key"></p>
</mtapp:setting>
<mtapp:setting
    id="region"
    label="<__trans phrase="region">">
<input type="text" name="region" value="<$mt:getvar name="region" escape="html"$>" />
<p class="hint"><__trans phrase="region"></p>
</mtapp:setting>
<mtapp:setting
    id="awscli_path"
    label="<__trans phrase="awscli_path">">
<input type="text" name="awscli_path" value="<$mt:getvar name="awscli_path" escape="html"$>" />
<p class="hint"><__trans phrase="awscli_path"></p>
</mtapp:setting>
__HTML__
}

sub _blog_config {
    return <<'__HTML__';
<mtapp:setting
    id="access_key"
    label="<__trans phrase="access_key">">
<input type="text" name="access_key" value="<$mt:getvar name="access_key" escape="html"$>" />
<p class="hint"><__trans phrase="access_key"></p>
</mtapp:setting>
<mtapp:setting
    id="secret_key"
    label="<__trans phrase="secret_key">">
<input type="text" name="secret_key" value="<$mt:getvar name="secret_key" escape="html"$>" />
<p class="hint"><__trans phrase="secret_key"></p>
</mtapp:setting>
<mtapp:setting
    id="region"
    label="<__trans phrase="region">">
<input type="text" name="region" value="<$mt:getvar name="region" escape="html"$>" />
<p class="hint"><__trans phrase="region"></p>
</mtapp:setting>
<mtapp:setting
    id="cf_dist_id"
    label="<__trans phrase="cf_dist_id">">
<input type="text" name="cf_dist_id" value="<$mt:getvar name="cf_dist_id" escape="html"$>" />
<p class="hint"><__trans phrase="cf_dist_id"></p>
</mtapp:setting>
<mtapp:setting
    id="cf_invalidation_path"
    label="<__trans phrase="cf_invalidation_path">">
<input type="text" name="cf_invalidation_path" value="<$mt:getvar name="cf_invalidation_path" escape="html"$>" />
<p class="hint"><__trans phrase="cf_invalidation_path"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_bucket"
    label="<__trans phrase="s3_bucket">">
<input type="text" name="s3_bucket" value="<$mt:getvar name="s3_bucket" escape="html"$>" />
<p class="hint"><__trans phrase="s3_bucket"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_dest_path"
    label="<__trans phrase="s3_dest_path">">
<input type="text" name="s3_dest_path" value="<$mt:getvar name="s3_dest_path" escape="html"$>" />
<p class="hint"><__trans phrase="s3_dest_path"></p>
</mtapp:setting>
__HTML__
}


1;
__END__
