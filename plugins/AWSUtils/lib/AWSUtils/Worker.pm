package AWSUtils::Worker;
use strict;
use warnings;
use utf8;
use base qw( TheSchwartz::Worker );
use TheSchwartz::Job;
use Data::Dumper;

sub grab_for    {5}
sub max_retries {5}
sub retry_delay {1} 

sub work {
    my $class = shift;

    my TheSchwartz::Job $job = shift;

    my $plugin = MT->component('AWSUtils');

    my @jobs;
    push @jobs, $job;
    if ( my $key = $job->coalesce ) {
        while ( my $job  = MT::TheSchwartz->instance->find_job_with_coalescing_value( $class, $key ) ) {
            push @jobs, $job;
        }
    }

    foreach $job (@jobs) {

        my $hash = $job->arg;
        my $aws_service = $job->coalesce;
        my $aws_task    = $hash->{task};

        my $blog = MT->model('blog')->load($hash->{blog_id}) or next;

        my $blog_config = $plugin->get_config_hash("blog:" . $blog->id) or return;
        my $system_config = $plugin->get_config_hash('system');

        #コンフィグ上書き
        my %config = (%$system_config, %$blog_config);
        
        my $aws = AWS::CLIWrapper->new(
            region      => $config{region},
            awscli_path => $config{awscli_path},
            nofork      => 1,
            timeout     => 600,
        );

        local $ENV{AWS_DEFAULT_OUTPUT}    = 'json';
        local $ENV{AWS_ACCESS_KEY_ID}     = $config{access_key};
        local $ENV{AWS_SECRET_ACCESS_KEY} = $config{secret_key};

        my $res;
        if ($aws_service eq 's3') {
            if ($aws_task eq 'sync') {
                my $s3 = 's3://' . $config{s3_bucket};
                $s3 .= $config{s3_dest_path} if defined $config{s3_dest_path};

                $res = $aws->s3('sync', [$blog->site_path, $s3], {
                    #exclude     => ['foo', 'bar'],
                });
            }
        }
        elsif ($aws_service eq 'cloudfront') {
            if ($aws_task eq 'create-invalidation') {
                $res = $aws->cloudfront(
                    'create-invalidation' => {
                        'distribution-id' => $config{cf_dist_id},
                        'paths' => $config{cf_invalidation_path},
                    },
                );
            }
        }

        if ($res) {
            $job->completed();  
        }
        else {
            MT->log($AWS::CLIWrapper::Error->{Message});
            $job->failed(sprintf'%s %s : %s', $aws_service, $aws_task, $AWS::CLIWrapper::Error->{Message});
        }    
    }

}

1;
__END__
