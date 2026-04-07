#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use lib 'plugins/AWSUtils/lib';
use lib 'plugins/AWSUtils/extlib';

# Load mock MT framework first
use MockMT;
MockMT::setup_default();

# Test that all modules compile
use_ok('AWSUtils::Utils');
use_ok('AWSUtils::Exec');
use_ok('AWSUtils::Tasks');
use_ok('AWSUtils::Worker');
use_ok('AWS::CLIWrapper');

done_testing();
