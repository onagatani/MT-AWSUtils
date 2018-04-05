package AWSUtils::Worker;
use strict;
use warnings;
use utf8;
use base qw( TheSchwartz::Worker );
use TheSchwartz::Job;
use Data::Dumper;
use AWSUtils::Exec;
use AWSUtils::Utils qw/create_config/;
use AWS::CLIWrapper;
use JSON;

sub grab_for    {5}
sub max_retries {5}
sub retry_delay {1} 

my $plugin = MT->component('AWSUtils');

sub work {
    my $class = shift;

    my TheSchwartz::Job $job = shift;

    my @jobs;
    push @jobs, $job;
    if ( my $key = $job->coalesce ) {
        while ( my $job  = MT::TheSchwartz->instance->find_job_with_coalescing_value( $class, $key ) ) {
            push @jobs, $job;
        }
    }

    foreach $job (@jobs) {

        my $args        = $job->arg;
        my $aws_service = $job->coalesce;
        my $aws_task    = $args->{task};

        my $blog = MT->model('blog')->load($args->{blog_id}) if $args->{blog_id};

        my $config = create_config($blog);
        my $aws = AWSUtils::Exec->new;

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
                $res .= $aws->cloudfront_invalidation(+{
                    cf_invalidation_path => $config->{cf_invalidation_path} || undef,
                    cf_dist_id           => $config->{cf_dist_id} || undef,
                });
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


        my $log;
        $log->{class} = $blog ? 'blog' : 'system';
        $log->{blog_id} = $blog->id if $blog;

        if ($res) {
            $job->completed();
            $log->{message} = 'Result of AWS CLI: ' . encode_json($res);
            $log->{level} = MT::Log::INFO();
        }
        else {
            my $errmes = $plugin->translate(
                "Execution of AWS CLI [_1] [_2] failed: [_3]", $aws_service, $aws_task,
                    $AWS::CLIWrapper::Error->{Message}  
            );

            $job->failed($errmes);

            $log->{message} = $errmes;
            $log->{level} = MT::Log::ERROR();
        }    
        MT->log($log);
    }

}

1;
__END__
