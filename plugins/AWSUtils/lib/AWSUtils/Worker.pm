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

        my $blog = MT->model('blog')->load($args->{blog_id});

        my $config = create_config($blog);
        my $aws = AWSUtils::Exec->new;

        my $res;
        if ($aws_service eq 's3') {
            if ($aws_task eq 'sync') {
                $res = $aws->s3_sync(+{
                    s3_bucket    => $config->{s3_bucket} || undef,
                    s3_dest_path => $config->{s3_dest_path} || undef,
                    exclude      => $args->{exclude} || undef,
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


        if ($res) {
            $job->completed();
        }
        else {
            $job->failed(sprintf'%s %s : %s', $aws_service, $aws_task, $AWS::CLIWrapper::Error->{Message});

            my $log = +{
                message => $plugin->translate(
                    "Execution of AWS [_1] [_2] failed: [_3]", $aws_service, $aws_task,
                        $AWS::CLIWrapper::Error->{Message}
                ),
                level   => MT::Log::ERROR(),
            };
            $log->{class} = $blog ? 'blog' : 'system';
            $log->{blog_id} = $blog->id if $blog;
            MT->log($log);
        }    
    }

}

1;
__END__
