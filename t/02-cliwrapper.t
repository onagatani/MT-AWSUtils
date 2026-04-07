#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 'plugins/AWSUtils/extlib';

use AWS::CLIWrapper;

###############################################################################
# param2opt tests
###############################################################################
subtest 'param2opt' => sub {

    subtest 'scalar value' => sub {
        my @result = AWS::CLIWrapper::param2opt('region', 'us-east-1');
        is_deeply(\@result, ['--region', 'us-east-1'], 'scalar becomes --key value');
    };

    subtest 'underscore converted to hyphen in key' => sub {
        my @result = AWS::CLIWrapper::param2opt('volume_id', 'vol-123');
        is_deeply(\@result, ['--volume-id', 'vol-123'], 'underscores to hyphens');
    };

    subtest 'output-file returns value only' => sub {
        my @result = AWS::CLIWrapper::param2opt('output_file', '/tmp/out');
        is_deeply(\@result, ['/tmp/out'], 'output-file has no --key prefix');
    };

    subtest 'array value' => sub {
        my @result = AWS::CLIWrapper::param2opt('instance_ids', ['i-111', 'i-222']);
        is($result[0], '--instance-ids', 'key is correct');
        is($result[1], 'i-111', 'first element');
        is($result[2], 'i-222', 'second element');
    };

    subtest 'hash value encoded as JSON' => sub {
        my @result = AWS::CLIWrapper::param2opt('filters', { Name => 'tag:env', Values => ['prod'] });
        is($result[0], '--filters', 'key is correct');
        # Value should be JSON
        like($result[1], qr/"Name"/, 'hash encoded as JSON');
    };

    subtest 'boolean true' => sub {
        my @result = AWS::CLIWrapper::param2opt('dry_run', $AWS::CLIWrapper::true);
        is_deeply(\@result, ['--dry-run'], 'true boolean produces flag only');
    };

    subtest 'boolean false' => sub {
        my @result = AWS::CLIWrapper::param2opt('dry_run', $AWS::CLIWrapper::false);
        is_deeply(\@result, ['--no-dry-run'], 'false boolean produces --no-flag');
    };
};

###############################################################################
# _compat_kv_uc tests
###############################################################################
subtest '_compat_kv_uc' => sub {
    my $compat = \&AWS::CLIWrapper::_compat_kv_uc;

    subtest 'upcases key/name/value/values' => sub {
        my $input = { key => 'k', name => 'n', value => 'v', values => [1,2] };
        my $result = $compat->($input);
        ok(exists $result->{Key},    'key -> Key');
        ok(exists $result->{Name},   'name -> Name');
        ok(exists $result->{Value},  'value -> Value');
        ok(exists $result->{Values}, 'values -> Values');
        ok(!exists $result->{key},   'original key removed');
    };

    subtest 'does not modify non-matching keys' => sub {
        my $input = { foo => 'bar', baz => 123 };
        my $result = $compat->($input);
        is($result->{foo}, 'bar', 'foo unchanged');
        is($result->{baz}, 123,   'baz unchanged');
    };

    subtest 'non-hash returns unchanged' => sub {
        my $input = 'string';
        my $result = $compat->($input);
        is($result, 'string', 'string passes through');
    };
};

###############################################################################
# Constructor tests
###############################################################################
subtest 'constructor' => sub {

    subtest 'default values' => sub {
        my $aws = AWS::CLIWrapper->new();
        is($aws->awscli_path, 'aws', 'default awscli_path is aws');
        is($aws->{timeout}, 30, 'default timeout is 30');
    };

    subtest 'custom awscli_path' => sub {
        my $aws = AWS::CLIWrapper->new(awscli_path => '/usr/local/bin/aws');
        is($aws->awscli_path, '/usr/local/bin/aws', 'custom path set');
    };

    subtest 'region sets --region opt' => sub {
        my $aws = AWS::CLIWrapper->new(region => 'eu-west-1');
        my @opt = @{$aws->{opt}};
        is($opt[0], '--region',   'region opt key');
        is($opt[1], 'eu-west-1',  'region opt value');
    };

    subtest 'profile sets --profile opt' => sub {
        my $aws = AWS::CLIWrapper->new(profile => 'myprofile');
        my @opt = @{$aws->{opt}};
        is($opt[0], '--profile',   'profile opt key');
        is($opt[1], 'myprofile',   'profile opt value');
    };

    subtest 'custom timeout' => sub {
        my $aws = AWS::CLIWrapper->new(timeout => 120);
        is($aws->{timeout}, 120, 'custom timeout set');
    };
};

###############################################################################
# Error object
###############################################################################
subtest 'Error global' => sub {
    is(ref $AWS::CLIWrapper::Error, 'HASH', 'Error is a hashref');
    ok(exists $AWS::CLIWrapper::Error->{Message}, 'Error has Message key');
    ok(exists $AWS::CLIWrapper::Error->{Code},    'Error has Code key');
};

###############################################################################
# Boolean objects
###############################################################################
subtest 'Boolean objects' => sub {
    is(ref $AWS::CLIWrapper::true,  'AWS::CLIWrapper::Boolean', 'true is Boolean');
    is(ref $AWS::CLIWrapper::false, 'AWS::CLIWrapper::Boolean', 'false is Boolean');
    is(${$AWS::CLIWrapper::true},  1, 'true value is 1');
    is(${$AWS::CLIWrapper::false}, 0, 'false value is 0');
};

###############################################################################
# Service method existence
###############################################################################
subtest 'service methods exist' => sub {
    my $aws = AWS::CLIWrapper->new();
    for my $service (qw(ec2 s3 s3api cloudfront cloudformation iam lambda
                        rds ecs eks elb elbv2 route53 sns sqs ssm
                        cloudwatch logs dynamodb secretsmanager wafv2
                        stepfunctions sagemaker sesv2)) {
        ok($aws->can($service), "method $service exists");
    }
};

###############################################################################
# AUTOLOAD for unknown services
###############################################################################
subtest 'AUTOLOAD catches unknown services' => sub {
    my $aws = AWS::CLIWrapper->new();
    ok($aws->can('AUTOLOAD'), 'AUTOLOAD is defined');
    # Cannot easily test execution without running aws CLI,
    # but we can verify the method resolution exists
};

done_testing();
