package MT::Plugin::AWSUtils;
use strict;
use warnings;
use base qw( MT::Plugin );
use AWS::CLIWrapper;

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
                    'tools:restart' => {
                        label             => "CloudFront Invalidation",
                        order             => 10100,
                        mode              => 'invalidation',
                        permission        => 'administer',
                        system_permission => 'administer',
                        view              => 'system',
                    },
                },
                methods => {
                    invalidation => \&_invalidation,
                },
            },
        },
    },
    system_config_template => \&_system_config,
    settings => MT::PluginSettings->new([
        ['access_key' ,{ Default => undef , Scope => 'system' }],
        ['secret_key' ,{ Default => undef , Scope => 'system' }],
        ['region'     ,{ Default => 'ap-northeast-1', Scope => 'system' }],
        ['awscli_path',{ Default => 'aws', Scope => 'system' }],
        ['cf_dist_id' ,{ Default => undef , Scope => 'system' }],
        ['cf_invalidation_path' ,{ Default => '/*' , Scope => 'system' }],
    ]),
});

MT->add_plugin( $plugin );

sub _invalidation {
    my $app = shift;

    my $config = $plugin->get_config_hash('system');

    local $ENV{AWS_ACCESS_KEY_ID}     = $config->{access_key};
    local $ENV{AWS_SECRET_ACCESS_KEY} = $config->{secret_key};
    local $ENV{AWS_DEFAULT_REGION}    = $config->{region};

    my $aws = AWS::CLIWrapper->new(
        awscli_path => $config->{awscli_path}
    );

    my $res = $aws->cloudfront(
        'create-invalidation' => {
            'distribution-id' => $config->{cf_dist_id},
            'paths' => $config->{cf_invalidation_path},
        },
    );

    if ($res) {
        warn 'SUCCESS';
    }
    else {
        warn $AWS::CLIWrapper::Error->{Code};
        warn $AWS::CLIWrapper::Error->{Message};
    }
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
__HTML__
}


1;
__END__

