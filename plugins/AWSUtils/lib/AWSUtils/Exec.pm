package AWSUtils::Exec;
use strict;
use warnings;
use utf8;
use AWSUtils::Utils qw/create_config/;
use AWS::CLIWrapper;
use Class::Accessor::Lite (
    new => 0,
    rw  => [ qw(config aws) ],
);

sub new {
    my ($class, $opt) = @_;
    my $self = bless $opt || +{}, $class;
    $self->_init();
    return $self;
}

sub _init {
    my $self = shift;

    my $config = create_config();
    $self->config($config);

    my $aws = AWS::CLIWrapper->new(
        region      => $self->config->{region},
        awscli_path => $self->config->{awscli_path},
        nofork      => 1,
        timeout     => 600,
    );
    $self->aws($aws);
}

sub _exec {
    my ($self, $method, $opt) = @_;

    local $ENV{AWS_DEFAULT_OUTPUT}    = 'json';
    local $ENV{AWS_ACCESS_KEY_ID}     = $self->config->{access_key};
    local $ENV{AWS_SECRET_ACCESS_KEY} = $self->config->{secret_key};

    return $self->$method($opt);
}

sub create_snapshot {
    shift->_exec('_create_snapshot', @_);
}
sub describe_snapshots {
    shift->_exec('_describe_snapshots', @_);
}
sub s3_sync {
    shift->_exec('_s3_sync', @_);
}
sub cloudfront_invalidation {
    shift->_exec('_cloudfront_invalidation', @_);
}

sub _s3_sync {
    my ($self, $opt) = @_;
    return unless $opt->{s3_bucket};

    my $s3 = 's3://' . $opt->{s3_bucket};
    $s3 .= '/' unless $s3 =~ m{/$};

    if (exists $opt->{s3_dest_path} && defined $opt->{s3_dest_path}) {
        $s3 =~ s{^/(.*?)$}{$1};
        $s3 .= $opt->{s3_dest_path};
    }

    my @exclude_path;
    if (my $exclude = $opt->{exclude}) {
        @exclude_path = split',', $exclude;
    }

    my $param = +{};
    $param->{exclude} = \@exclude_path if scalar @exclude_path;

    return $self->aws->s3('sync', [$opt->{local_path}, $s3], $param);
}

sub _cloudfront_invalidation {
    my ($self, $opt) = @_;
    return unless $opt->{cf_dist_id};

    $opt->{cf_invalidation_path} = '/*' unless defined $opt->{cf_invalidation_path};

    return $self->aws->cloudfront(
        'create-invalidation' => {
            'distribution-id' => $opt->{cf_dist_id},
            'paths' => $opt->{cf_invalidation_path},
        },
    );
} 

sub _create_snapshot {
    my ($self, $opt) = @_;
    return unless $self->config->{ec2_volume_id};

    return  $self->aws->ec2(
        'create-snapshot' => {
            'volume-id'   => $self->config->{ec2_volume_id},
            'description' => $self->config->{ec2_volume_id},
        },
    );
}

sub _describe_snapshots {
    my ($self, $opt) = @_;
    return unless $self->config->{ec2_volume_id};

    my $value = sprintf'Name=volume-id,Values=%s', $self->config->{ec2_volume_id};

    return $self->aws->ec2(
        'describe-snapshots' => {
            'filters'   => $value,
        },
    );
}


1;
__END__
