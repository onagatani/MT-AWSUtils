package MT::Plugin::AWSUtils;
use strict;
use warnings;
use base qw( MT::Plugin );
use Data::Dumper;
use MT::TheSchwartz;
use MT::PluginData; 
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
                'Utility for AWS.'     => 'AWS用のユーティリティープラグイン',
                'access_key'           => 'AWSアクセスキー',
                'secret_key'           => 'AWSシークレットキー',
                'region'               => 'リージョン',
                'awscli_path'          => 'awscliコマンドのパス',
                'cf_dist_id'           => 'CloudFrontディストリビューションID',
                'cf_invalidation_path' => 'CloudFrontのキャッシュを削除するパス',
                's3_bucket'            => '転送先のS3バケット',
                's3_dest_path'         => '転送先のS3のパス',
                'ec2_volume_id'        => 'EBS ボリュームID',
                'hint_access_key'      => 'システム設定を継承しますが、Webサイト設定で上書き可能です',
                'hint_secret_key'           => 'システム設定を継承しますが、Webサイト設定で上書き可能です',
                'hint_region'               => 'ap-northeast-1などを指定します',
                'hint_awscli_path'          => '通常は設定しなくても問題ありません',
                'hint_cf_dist_id'           => 'CloudFrontのコンソール画面で確認してください',
                'hint_cf_invalidation_path' => '通常は/*のように設定します',
                'hint_s3_bucket'            => 's3://などは必要ありません',
                'hint_s3_dest_path'         => 'S3内のディレクトリを指定します',
                'hint_ec2_volume_id'        => 'EC2のIDではなくEBSボリュームIDを指定して下さい',
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
                    'AWSUtils:ec2describesnapshots' => {
                        label             => "EC2 Describe Snapshots",
                        order             => 200300,
                        mode              => 'ec2describe',
                        permission        => 'administer',
                        system_permission => 'administer',
                        condition         => \&_check_perm,
                        view              => 'system',
                    },
                    'AWSUtils:ec2createsnapshot' => {
                        label             => "EC2 Create Snapshot",
                        order             => 200300,
                        mode              => 'ec2snapshot',
                        permission        => 'administer',
                        system_permission => 'administer',
                        condition         => \&_check_perm,
                        view              => 'system',
                    },
                },
                methods => {
                    invalidation => \&_invalidation,
                    s3sync       => \&_s3sync,
                    ec2snapshot  => \&_ec2snapshot,
                    ec2describe  => \&_ec2describe,
                },
            },
        },
        task_workers => {
            awsutils_worker => { 
                class => 'AWSUtils::Worker',
                label => 'AWSUtils Worker',
            },
        },
        tasks => {
            'awsutils_ec2describe' => {
                name => 'AWSUtils::EC2::DescribeSnapshots',
                frequency => 60,
                code => "AWSUtils::Tasks::ec2describesnapshots",
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
        ['ec2_volume_id' ,{ Default => undef, Scope => 'system' }],
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

sub _ec2describe {
    my $app = shift;

    my $data = MT::PluginData->load({
        plugin => 'AWSUtils',
        key    => 'describe_snapshots'
    });

    my $tmpl = $plugin->load_tmpl('ec2describe.tmpl')
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", 'ec2describe.tmpl'));

    my $tmpl_param;
    $tmpl_param->{data} = $data->data();

    return $app->build_page($tmpl, $tmpl_param);
}

sub _ec2snapshot {
    my $app = shift;

    my $job = TheSchwartz::Job->new();

    my $config = $plugin->get_config_hash('system');
    my $tmpl_param;

    if ($config->{ec2_volume_id}) {
        $tmpl_param->{ec2_volume_id} = $config->{ec2_volume_id};
    }
    else {
        $tmpl_param->{errmes} =
            $plugin->translate("Couldn't load ec2-volume-id.");
    }

    $job->funcname( 'AWSUtils::Worker' );
    $job->arg({
       blog_id => '0',
       task    => 'create-snapshot',
    });
    $job->uniqkey('0' . "::EC2::CreateSnapshot");
    $job->coalesce('ec2');
    MT::TheSchwartz->insert($job);

    my $tmpl_name = 'ec2_createsnapshot.tmpl';

    my $tmpl = $plugin->load_tmpl($tmpl_name)
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", $tmpl_name));

    return $app->build_page($tmpl, $tmpl_param);
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
<p class="hint"><__trans phrase="hint_access_key"></p>
</mtapp:setting>
<mtapp:setting
    id="secret_key"
    label="<__trans phrase="secret_key">">
<input type="text" name="secret_key" value="<$mt:getvar name="secret_key" escape="html"$>" />
<p class="hint"><__trans phrase="hint_secret_key"></p>
</mtapp:setting>
<mtapp:setting
    id="region"
    label="<__trans phrase="region">">
<input type="text" name="region" value="<$mt:getvar name="region" escape="html"$>" />
<p class="hint"><__trans phrase="hint_region"></p>
</mtapp:setting>
<mtapp:setting
    id="awscli_path"
    label="<__trans phrase="awscli_path">">
<input type="text" name="awscli_path" value="<$mt:getvar name="awscli_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint_awscli_path"></p>
</mtapp:setting>
<mtapp:setting
    id="ec2_volume_id"
    label="<__trans phrase="ec2_volume_id">">
<input type="text" name="ec2_volume_id" value="<$mt:getvar name="ec2_volume_id" escape="html"$>" />
<p class="hint"><__trans phrase="hint_ec2_volume_id"></p>
</mtapp:setting>
__HTML__
}

sub _blog_config {
    return <<'__HTML__';
<mtapp:setting
    id="access_key"
    label="<__trans phrase="access_key">">
<input type="text" name="access_key" value="<$mt:getvar name="access_key" escape="html"$>" />
<p class="hint"><__trans phrase="hint_access_key"></p>
</mtapp:setting>
<mtapp:setting
    id="secret_key"
    label="<__trans phrase="secret_key">">
<input type="text" name="secret_key" value="<$mt:getvar name="secret_key" escape="html"$>" />
<p class="hint"><__trans phrase="hint_secret_key"></p>
</mtapp:setting>
<mtapp:setting
    id="region"
    label="<__trans phrase="region">">
<input type="text" name="region" value="<$mt:getvar name="region" escape="html"$>" />
<p class="hint"><__trans phrase="hint_region"></p>
</mtapp:setting>
<mtapp:setting
    id="cf_dist_id"
    label="<__trans phrase="cf_dist_id">">
<input type="text" name="cf_dist_id" value="<$mt:getvar name="cf_dist_id" escape="html"$>" />
<p class="hint"><__trans phrase="hint_cf_dist_id"></p>
</mtapp:setting>
<mtapp:setting
    id="cf_invalidation_path"
    label="<__trans phrase="cf_invalidation_path">">
<input type="text" name="cf_invalidation_path" value="<$mt:getvar name="cf_invalidation_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint_cf_invalidation_path"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_bucket"
    label="<__trans phrase="s3_bucket">">
<input type="text" name="s3_bucket" value="<$mt:getvar name="s3_bucket" escape="html"$>" />
<p class="hint"><__trans phrase="hint_s3_bucket"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_dest_path"
    label="<__trans phrase="s3_dest_path">">
<input type="text" name="s3_dest_path" value="<$mt:getvar name="s3_dest_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint_s3_dest_path"></p>
</mtapp:setting>
__HTML__
}


1;
__END__
