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
                'AWS Access Key'       => 'AWSアクセスキー',
                'AWS Secret Key'       => 'AWSシークレットキー',
                'region'               => 'リージョン',
                'awscli path'          => 'awscliコマンドのパス',
                'CloudFront Distribution ID' => 'CloudFrontディストリビューションID',
                'CloudFront Invalidation Path' => 'CloudFrontのキャッシュを削除するパス',
                'S3 Bucket'            => '転送先のS3バケット',
                'S3 Destination Path'         => '転送先のS3のパス',
                'EC2 EBS Volume ID'        => 'EBS ボリュームID',
                'hint: AWS Access Key'  => 'Cloudfront/s3/ebsの権限が必要になります',
                'hint: AWS Secret Key'  => 'Cloudfront/s3/ebsの権限が必要になります',
                'hint: region'               => 'ap-northeast-1などを指定します',
                'hint: awscli path'          => '通常は設定しなくても問題ありません',
                'hint: CloudFront Distribution ID'           => 'CloudFrontのコンソール画面で確認してください',
                'hint: CloudFront Invalidation Path' => '通常は/*のように設定します',
                'hint: S3 Bucket'            => 's3://などは必要ありません',
                'hint: S3 Destination Path'         => 'S3内のディレクトリを指定します',
                'hint: EC2 EBS Volume ID' => 'EC2のIDではなくEBSボリュームIDを指定して下さい(vol-から始まります)',
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
                frequency => 1,
                code => "AWSUtils::Tasks::ec2describesnapshots",
            },
        },
    },
    system_config_template => \&_system_config,
    blog_config_template => \&_blog_config,
    settings => MT::PluginSettings->new([
        ['access_key' ,{ Default => undef , Scope => 'system' }],
        ['secret_key' ,{ Default => undef , Scope => 'system' }],
        ['region'     ,{ Default => 'ap-northeast-1', Scope => 'system' }],
        ['ec2_volume_id' ,{ Default => undef, Scope => 'system' }],
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

sub _ec2describe {
    my $app = shift;

    my $data = MT::PluginData->load({
        plugin => 'AWSUtils',
        key    => 'describe_snapshots'
    });

    my $tmpl = $plugin->load_tmpl('ec2_describesnapshot.tmpl')
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", 'ec2describe.tmpl'));

    my $tmpl_param;
    $tmpl_param->{data} = $data->data() if $data;

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

    my $tmpl_name = 's3_sync.tmpl';

    my $tmpl = $plugin->load_tmpl($tmpl_name)
        or return $app->error($plugin->translate("Couldn't load template file. : [_1]", $tmpl_name));

    return $app->build_page($tmpl, +{});
}

sub _system_config {
    return <<'__HTML__';
<mtapp:setting
    id="access_key"
    label="<__trans phrase="AWS Access Key">">
<input type="text" name="access_key" value="<$mt:getvar name="access_key" escape="html"$>" />
<p class="hint"><__trans phrase="hint: AWS Access Key"></p>
</mtapp:setting>
<mtapp:setting
    id="secret_key"
    label="<__trans phrase="AWS Secret Key">">
<input type="text" name="secret_key" value="<$mt:getvar name="secret_key" escape="html"$>" />
<p class="hint"><__trans phrase="hint: AWS Secret Key"></p>
</mtapp:setting>
<mtapp:setting
    id="region"
    label="<__trans phrase="region">">
<input type="text" name="region" value="<$mt:getvar name="region" escape="html"$>" />
<p class="hint"><__trans phrase="hint: region"></p>
</mtapp:setting>
<mtapp:setting
    id="awscli_path"
    label="<__trans phrase="awscli path">">
<input type="text" name="awscli_path" value="<$mt:getvar name="awscli_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint: awscli path"></p>
</mtapp:setting>
<mtapp:setting
    id="ec2_volume_id"
    label="<__trans phrase="EC2 EBS Volume ID">">
<input type="text" name="ec2_volume_id" value="<$mt:getvar name="ec2_volume_id" escape="html"$>" />
<p class="hint"><__trans phrase="hint: EC2 EBS Volume ID"></p>
</mtapp:setting>
__HTML__
}

sub _blog_config {
    return <<'__HTML__';
<mtapp:setting
    id="cf_dist_id"
    label="<__trans phrase="CloudFront Distribution ID">">
<input type="text" name="cf_dist_id" value="<$mt:getvar name="cf_dist_id" escape="html"$>" />
<p class="hint"><__trans phrase="hint: CloudFront Distribution ID"></p>
</mtapp:setting>
<mtapp:setting
    id="cf_invalidation_path"
    label="<__trans phrase="CloudFront Invalidation Path">">
<input type="text" name="cf_invalidation_path" value="<$mt:getvar name="cf_invalidation_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint: CloudFront Invalidation Path"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_bucket"
    label="<__trans phrase="S3 Bucket">">
<input type="text" name="s3_bucket" value="<$mt:getvar name="s3_bucket" escape="html"$>" />
<p class="hint"><__trans phrase="hint: S3 Bucket"></p>
</mtapp:setting>
<mtapp:setting
    id="s3_dest_path"
    label="<__trans phrase="S3 Destination Path">">
<input type="text" name="s3_dest_path" value="<$mt:getvar name="s3_dest_path" escape="html"$>" />
<p class="hint"><__trans phrase="hint: S3 Destination Path"></p>
</mtapp:setting>
__HTML__
}


1;
__END__
