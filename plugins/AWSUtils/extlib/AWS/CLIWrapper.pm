package AWS::CLIWrapper;

use 5.008001;
use strict;
use warnings;

our $VERSION = '1.27';

use version;
use JSON 2;
use IPC::Cmd;
use String::ShellQuote;

our $Error = { Message => '', Code => '' };

our $true  = do { bless \(my $dummy = 1), "AWS::CLIWrapper::Boolean" };
our $false = do { bless \(my $dummy = 0), "AWS::CLIWrapper::Boolean" };

my $AWSCLI_VERSION = undef;

sub new {
    my($class, %param) = @_;

    my @opt = ();
    for my $k (qw(region profile endpoint_url output)) {
        if (my $v = delete $param{$k}) {
            push @opt, param2opt($k, $v);
        }
    }

    my $self = bless {
        opt  => \@opt,
        json => JSON->new,
        awscli_path => $param{awscli_path} // 'aws',
        timeout => $param{timeout} // 30,
    }, $class;

    return $self;
}

sub awscli_path {
    my ($self) = @_;
    return $self->{awscli_path};
}

sub awscli_version {
    my ($self) = @_;
    unless (defined $AWSCLI_VERSION) {
        $AWSCLI_VERSION = do {
            my $awscli_path = $self->awscli_path;
            my $vs = qx($awscli_path --version 2>&1) || '';
            my $v;
            if ($vs =~ m{/([0-9]+\.[0-9]+\.[0-9]+)}) {
                $v = $1;
            } else {
                $v = 0;
            }
            version->parse($v);
        };
    }
    return $AWSCLI_VERSION;
}

sub _is_v2 {
    my ($self) = @_;
    return $self->awscli_version >= version->parse('2.0.0');
}

sub param2opt {
    my($k, $v) = @_;

    my @v;

    $k =~ s/_/-/g;
    $k = '--'.$k;

    my $type = ref $v;
    if (! $type) {
        if ($k eq '--output-file') {
            return $v;
        } else {
            push @v, $v;
        }
    } elsif ($type eq 'ARRAY') {
        push @v, map { ref($_) ? encode_json(_compat_kv($_)) : $_ } @$v;
    } elsif ($type eq 'HASH') {
        push @v, encode_json(_compat_kv($v));
    } elsif ($type eq 'AWS::CLIWrapper::Boolean') {
        if ($$v == 1) {
            return ($k);
        } else {
            my $no_k = $k;
            $no_k =~ s/^--/--no-/;
            return ($no_k);
        }
    } else {
        push @v, $v;
    }

    return ($k, @v);
}

sub _compat_kv_uc {
    my $v = shift;
    my $type = ref $v;

    if ($type && $type eq 'HASH') {
        for my $hk (keys %$v) {
            if ($hk =~ /^(?:key|name|values|value)$/) {
                $v->{ucfirst($hk)} = delete $v->{$hk};
            }
        }
    }

    return $v;
}
*_compat_kv = *_compat_kv_uc;

sub json { $_[0]->{json} }

sub _execute {
    my $self    = shift;
    my $service = shift;
    my $operation = shift;
    my @cmd = ($self->awscli_path, @{$self->{opt}}, $service, $operation);
    if ($service eq 'ec2' && $operation eq 'wait') {
        push(@cmd, shift @_);
    }
    if (ref($_[0]) eq 'ARRAY') {
        push @cmd, @{ shift @_ };
    }
    my($param, %opt) = @_;

    if ($service eq 's3' && !$self->_is_v2) {
        if ($self->awscli_version >= version->parse('0.15.0')) {
            if ($operation !~ /^(?:cp|ls|mb|mv|rb|rm|sync|website)$/) {
                return $self->s3api($operation, @_);
            }
        }
    } elsif ($service eq 's3api' && !$self->_is_v2) {
        if ($self->awscli_version < version->parse('0.15.0')) {
            return $self->s3($operation, @_);
        }
    }

    if ($param) {
        while (my($k, $v) = each %$param) {
            my @o = param2opt($k, $v);
            if ($service eq 's3' && $k =~ /^(?:include|exclude)$/) {
                my $optk = shift @o;
                @o = map { $optk => $_ } @o;
            }
            push @cmd, @o;
        }
    }

    # aws-cli v2: ensure JSON output and disable pager
    unless (grep { $_ eq '--output' } @cmd) {
        push @cmd, '--output', 'json';
    }
    if ($self->_is_v2) {
        unless (grep { $_ eq '--no-cli-pager' } @cmd) {
            push @cmd, '--no-cli-pager';
        }
    }

    @cmd = map { shell_quote($_) } @cmd;
    warn "cmd: ".join(' ', @cmd) if $ENV{AWSCLI_DEBUG};

    my $timeout = $opt{timeout} || $self->{timeout} || 30;

    my $ret;
    if (exists $opt{'nofork'} && $opt{'nofork'}) {
        my($ok, $err, $buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
            command => join(' ', @cmd),
            timeout => $timeout,
        );
        $ret->{stdout} = join "", @$stdout_buf;
        $ret->{err_msg} = (defined $err ? "$err\n" : "") . join "", @$stderr_buf;
        if ($ok) {
            $ret->{exit_code} = 0;
            $ret->{timeout} = 0;
        } else {
            $ret->{exit_code} = 2;
            $ret->{timeout} = 1 if defined $err && $err =~ /^IPC::Cmd::TimeOut:/;
        }
        print "";
    } else {
        $ret = IPC::Cmd::run_forked(join(' ', @cmd), {
            timeout => $timeout,
        });
    }

    if ($ret->{exit_code} == 0 && $ret->{timeout} == 0) {
        my $json = $ret->{stdout};
        warn sprintf("%s.%s[%s]: %s\n",
                     $service, $operation, 'OK', $json,
                    ) if $ENV{AWSCLI_DEBUG};
        local $@;
        my($decoded) = eval {
            $self->json->decode_prefix($json);
        };
        if ($@) {
            if ($ENV{AWSCLI_DEBUG}) {
                warn $@;
                warn qq|stdout: "$json"|;
                warn qq|err_msg: "$ret->{err_msg}"|;
            }
            return $json || 'success';
        }
        return $decoded;
    } else {
        my $stdout_str = $ret->{stdout};
        if ($stdout_str && $stdout_str =~ /^\s*\{/) {
            my $json = $stdout_str;
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $json,
                        ) if $ENV{AWSCLI_DEBUG};
            local $@;
            my($decoded) = eval { $self->json->decode_prefix($json) };
            if ($@ || !$decoded) {
                $Error = { Message => $json, Code => 'Unknown' };
            } elsif (exists $decoded->{Errors} && ref($decoded->{Errors}) eq 'ARRAY') {
                $Error = $decoded->{Errors}[0];
            } elsif (exists $decoded->{Error}) {
                $Error = $decoded->{Error};
            } elsif (exists $decoded->{Response}{Errors}{Error}) {
                $Error = $decoded->{Response}{Errors}{Error};
            } else {
                $Error = { Message => $json, Code => 'Unknown' };
            }
        } else {
            my $msg = $ret->{err_msg} || 'Unknown error';
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $msg,
                        ) if $ENV{AWSCLI_DEBUG};
            $Error = { Message => $msg, Code => 'Unknown' };
       }
        return;
    }
}

sub acm                { shift->_execute('acm', @_) }
sub apigateway         { shift->_execute('apigateway', @_) }
sub application_autoscaling { shift->_execute('application-autoscaling', @_) }
sub athena             { shift->_execute('athena', @_) }
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub backup             { shift->_execute('backup', @_) }
sub batch              { shift->_execute('batch', @_) }
sub budgets            { shift->_execute('budgets', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudfront         { shift->_execute('cloudfront', @_) }
sub cloudhsm           { shift->_execute('cloudhsm', @_) }
sub cloudsearch        { shift->_execute('cloudsearch', @_) }
sub cloudsearchdomain  { shift->_execute('cloudsearchdomain', @_) }
sub cloudtrail         { shift->_execute('cloudtrail', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub codecommit         { shift->_execute('codecommit', @_) }
sub codepipeline       { shift->_execute('codepipeline', @_) }
sub cognito_identity   { shift->_execute('cognito-identity', @_) }
sub cognito_idp        { shift->_execute('cognito-idp', @_) }
sub cognito_sync       { shift->_execute('cognito-sync', @_) }
sub configservice      { shift->_execute('configservice', @_) }
sub configure          { shift->_execute('configure', @_) }
sub datapipeline       { shift->_execute('datapipeline', @_) }
sub deploy             { shift->_execute('deploy', @_) }
sub devicefarm         { shift->_execute('devicefarm', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub discovery          { shift->_execute('discovery', @_) }
sub dms                { shift->_execute('dms', @_) }
sub ds                 { shift->_execute('ds', @_) }
sub dynamodb           { shift->_execute('dynamodb', @_) }
sub dynamodbstreams    { shift->_execute('dynamodbstreams', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub ecr                { shift->_execute('ecr', @_) }
sub ecs                { shift->_execute('ecs', @_) }
sub efs                { shift->_execute('efs', @_) }
sub eks                { shift->_execute('eks', @_) }
sub elasticache        { shift->_execute('elasticache', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elastictranscoder  { shift->_execute('elastictranscoder', @_) }
sub elb                { shift->_execute('elb', @_) }
sub elbv2              { shift->_execute('elbv2', @_) }
sub emr                { shift->_execute('emr', @_) }
sub es                 { shift->_execute('es', @_) }
sub events             { shift->_execute('events', @_) }
sub firehose           { shift->_execute('firehose', @_) }
sub gamelift           { shift->_execute('gamelift', @_) }
sub glacier            { shift->_execute('glacier', @_) }
sub glue               { shift->_execute('glue', @_) }
sub iam                { shift->_execute('iam', @_) }
sub importexport       { shift->_execute('importexport', @_) }
sub inspector          { shift->_execute('inspector', @_) }
sub iot                { shift->_execute('iot', @_) }
sub iot_data           { shift->_execute('iot-data', @_) }
sub kinesis            { shift->_execute('kinesis', @_) }
sub kinesisanalytics   { shift->_execute('kinesisanalytics', @_) }
sub kms                { shift->_execute('kms', @_) }
sub lambda             { shift->_execute('lambda', @_) }
sub lightsail          { shift->_execute('lightsail', @_) }
sub logs               { shift->_execute('logs', @_) }
sub machinelearning    { shift->_execute('machinelearning', @_) }
sub marketplacecommerceanalytics { shift->_execute('marketplacecommerceanalytics', @_) }
sub mediaconvert       { shift->_execute('mediaconvert', @_) }
sub meteringmarketplace { shift->_execute('meteringmarketplace', @_) }
sub opsworks           { shift->_execute('opsworks', @_) }
sub organizations      { shift->_execute('organizations', @_) }
sub polly              { shift->_execute('polly', @_) }
sub rds                { shift->_execute('rds', @_) }
sub redshift           { shift->_execute('redshift', @_) }
sub rekognition        { shift->_execute('rekognition', @_) }
sub route53            { shift->_execute('route53', @_) }
sub route53domains     { shift->_execute('route53domains', @_) }
sub s3                 { shift->_execute('s3', @_) }
sub s3api              { shift->_execute('s3api', @_) }
sub sagemaker          { shift->_execute('sagemaker', @_) }
sub sdb                { shift->_execute('sdb', @_) }
sub secretsmanager     { shift->_execute('secretsmanager', @_) }
sub servicecatalog     { shift->_execute('servicecatalog', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sesv2              { shift->_execute('sesv2', @_) }
sub sms                { shift->_execute('sms', @_) }
sub snowball           { shift->_execute('snowball', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub ssm                { shift->_execute('ssm', @_) }
sub stepfunctions      { shift->_execute('stepfunctions', @_) }
sub storagegateway     { shift->_execute('storagegateway', @_) }
sub sts                { shift->_execute('sts', @_) }
sub support            { shift->_execute('support', @_) }
sub swf                { shift->_execute('swf', @_) }
sub waf                { shift->_execute('waf', @_) }
sub wafv2              { shift->_execute('wafv2', @_) }
sub workspaces         { shift->_execute('workspaces', @_) }

# Catch-all for any service not listed above
sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;
    my $service = $AUTOLOAD;
    $service =~ s/.*:://;
    return if $service eq 'DESTROY';
    $service =~ s/_/-/g;
    return $self->_execute($service, @_);
}

1;

__END__
