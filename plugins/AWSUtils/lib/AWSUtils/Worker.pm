package AWSUtils::Worker;
use strict;
use warnings;
use utf8;
use base qw( TheSchwartz::Worker );
use TheSchwartz::Job;
use Data::Dumper;
use AWS::CLIWrapper;
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

        my $blog = MT->model('blog')->load($hash->{blog_id});

        my $blog_config = $plugin->get_config_hash("blog:" . $blog->id) if $blog;
        my $system_config = $plugin->get_config_hash('system');

        my %config = %$system_config;

        if ($blog) {
            for my $key (keys %$blog_config) {
                if (exists $blog_config->{$key} && defined $blog_config->{$key}) {
                    $config{$key} = $blog_config->{$key};
                }
            }
        }
        
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
                next unless $config{s3_bucket};

                my $s3 = 's3://' . $config{s3_bucket};
                $s3 .= '/' unless $s3 =~ m{/$};

                if (my $s3_dest_path = $config{s3_dest_path}) {
                    $s3 =~ s{^/(.*?)$}{$1};
                    $s3 .= $config{s3_dest_path};
                }

                my @exclude_path;
                if (my $exclude = $hash->{exclude}) {
                    @exclude_path = split',', $exclude;
                }

                my $opt = +{};
                $opt->{exclude} = \@exclude_path if scalar @exclude_path;

                $res = $aws->s3('sync', [$blog->site_path, $s3], $opt);
            }
        }
        elsif ($aws_service eq 'cloudfront') {
            if ($aws_task eq 'create-invalidation') {
                next unless $config{cf_dist_id};
                $config{cf_invalidation_path} = '/*' unless defined $config{cf_invalidation_path};

                $res = $aws->cloudfront(
                    'create-invalidation' => {
                        'distribution-id' => $config{cf_dist_id},
                        'paths' => $config{cf_invalidation_path},
                    },
                );
            }
        }
        elsif ($aws_service eq 'ec2') {
            if ($aws_task eq 'create-snapshot') {
                next unless $config{ec2_volume_id};

                $res = $aws->ec2(
                    'create-snapshot' => {
                        'volume-id'   => $config{ec2_volume_id},
                        'description' => $config{ec2_volume_id},
                    },
                );
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
