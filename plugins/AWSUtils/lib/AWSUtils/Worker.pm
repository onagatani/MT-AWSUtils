package AWSUtils::Worker;
use strict;
use warnings;
use utf8;
use base qw( TheSchwartz::Worker );
use TheSchwartz::Job;
use AWSUtils::Exec;
use AWSUtils::Utils qw/create_config/;
use AWS::CLIWrapper;
use JSON 2;

sub grab_for    {600}
sub max_retries {3}
sub retry_delay {60}

sub work {
    my $class = shift;
    my TheSchwartz::Job $job = shift;

    my $plugin = MT->component('AWSUtils');

    my @jobs;
    push @jobs, $job;
    if ( my $key = $job->coalesce ) {
        while ( my $coalesced_job = MT::TheSchwartz->instance->find_job_with_coalescing_value( $class, $key ) ) {
            push @jobs, $coalesced_job;
        }
    }

    foreach my $current_job (@jobs) {

        my $args        = $current_job->arg;
        my $aws_service = $current_job->coalesce;
        my $aws_task    = $args->{task};

        my $blog;
        if ($args->{blog_id}) {
            $blog = MT->model('blog')->load($args->{blog_id});
        }

        my $config = create_config($blog);
        my $aws = AWSUtils::Exec->new(blog => $blog);

        my $res;
        if ($aws_service eq 's3') {
            if ($aws_task eq 'sync') {
                next unless $blog;
                $res = $aws->s3_sync(+{
                    local_path   => $blog->site_path,
                    s3_bucket    => $config->{s3_bucket} || undef,
                    s3_dest_path => $config->{s3_dest_path} || undef,
                    exclude      => $args->{exclude} || undef,
                });
                if ($config->{cf_dist_id}) {
                    my $cf_res = $aws->cloudfront_invalidation(+{
                        cf_invalidation_path => $config->{cf_invalidation_path} || undef,
                        cf_dist_id           => $config->{cf_dist_id} || undef,
                    });
                    if ($res && $cf_res) {
                        $res = { s3_sync => $res, cloudfront => $cf_res };
                    }
                }
            }
        }
        elsif ($aws_service eq 'cloudfront') {
            if ($aws_task eq 'create-invalidation') {
                $res = $aws->cloudfront_invalidation(+{
                    cf_invalidation_path => $config->{cf_invalidation_path} || undef,
                    cf_dist_id           => $config->{cf_dist_id} || undef,
                });
            }
        }
        elsif ($aws_service eq 'ec2') {
            if ($aws_task eq 'create-snapshot') {
                $res = $aws->create_snapshot();
            }
        }
        else {
            next;
        }

        my $log = {};
        $log->{class} = $blog ? 'blog' : 'system';
        $log->{blog_id} = $blog ? $blog->id : 0;
        $log->{category} = 'AWSUtils';

        if ($res) {
            $current_job->completed();
            my $json_res = ref($res) ? encode_json($res) : "$res";
            $log->{message} = 'Result of AWS CLI: ' . $json_res;
            $log->{level} = MT::Log::INFO();
        }
        else {
            my $error_msg = $AWS::CLIWrapper::Error->{Message} || 'Unknown error';
            my $errmes = $plugin
                ? $plugin->translate(
                    "Execution of AWS CLI [_1] [_2] failed: [_3]",
                    $aws_service, $aws_task, $error_msg
                  )
                : "Execution of AWS CLI $aws_service $aws_task failed: $error_msg";

            $current_job->failed($errmes);

            $log->{message} = $errmes;
            $log->{level} = MT::Log::ERROR();
        }
        MT->log($log);
    }
}

1;
__END__
