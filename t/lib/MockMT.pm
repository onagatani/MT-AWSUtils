package MockMT;
use strict;
use warnings;

# This module sets up a complete mock MT framework for unit testing.
# Usage: use lib 't/lib'; use MockMT;

# Pre-register all mock packages in %INC so that 'use' in the real
# plugin modules finds them without looking for .pm files on disk.
BEGIN {
    $INC{'MT.pm'}                = __FILE__;
    $INC{'MT/Log.pm'}            = __FILE__;
    $INC{'MT/Plugin.pm'}         = __FILE__;
    $INC{'MT/PluginData.pm'}     = __FILE__;
    $INC{'MT/PluginSettings.pm'} = __FILE__;
    $INC{'MT/TheSchwartz.pm'}    = __FILE__;
    $INC{'MT/App.pm'}            = __FILE__;
    $INC{'TheSchwartz/Job.pm'}   = __FILE__;
    $INC{'TheSchwartz/Worker.pm'}= __FILE__;
}

###############################################################################
# MT::Log - log level constants
###############################################################################
package MT::Log;
use strict;
use warnings;

use constant INFO    => 1;
use constant WARNING => 2;
use constant ERROR   => 4;
use constant SECURITY => 8;
use constant DEBUG   => 16;

1;

###############################################################################
# MT::PluginSettings
###############################################################################
package MT::PluginSettings;
use strict;
use warnings;

sub new {
    my ($class, $settings) = @_;
    return bless { settings => $settings }, $class;
}

1;

###############################################################################
# MT::PluginData
###############################################################################
package MT::PluginData;
use strict;
use warnings;

my @_all_data;

sub new {
    my ($class) = @_;
    return bless { _data => undef, _plugin => undef, _key => undef }, $class;
}

sub load {
    my ($class, $terms) = @_;
    for my $d (@_all_data) {
        if ($d->{_plugin} eq $terms->{plugin} && $d->{_key} eq $terms->{key}) {
            return $d;
        }
    }
    return undef;
}

sub plugin {
    my ($self, $val) = @_;
    $self->{_plugin} = $val if defined $val;
    return $self->{_plugin};
}

sub key {
    my ($self, $val) = @_;
    $self->{_key} = $val if defined $val;
    return $self->{_key};
}

sub data {
    my ($self, $val) = @_;
    $self->{_data} = $val if defined $val;
    return $self->{_data};
}

sub save {
    my $self = shift;
    # Remove existing entry with same plugin+key
    @_all_data = grep {
        !($_->{_plugin} eq $self->{_plugin} && $_->{_key} eq $self->{_key})
    } @_all_data;
    push @_all_data, $self;
    return 1;
}

sub _clear_all {
    @_all_data = ();
}

1;

###############################################################################
# MT::Plugin (mock)
###############################################################################
package MT::Plugin;
use strict;
use warnings;

sub new {
    my ($class, $args) = @_;
    if (ref $args eq 'HASH') {
        return bless { %$args }, $class;
    }
    return bless {}, $class;
}

sub get_config_hash {
    my ($self, $scope) = @_;
    my $configs = $self->{_mock_configs} || {};
    my $config = $configs->{$scope};
    return { %{ $config || {} } };
}

sub translate {
    my ($self, $fmt, @args) = @_;
    my $result = $fmt;
    for my $i (0 .. $#args) {
        my $n = $i + 1;
        my $arg = defined $args[$i] ? $args[$i] : '';
        $result =~ s/\[_$n\]/$arg/g;
    }
    return $result;
}

sub load_tmpl {
    my ($self, $name) = @_;
    return bless { name => $name }, 'MockTemplate';
}

sub _set_config {
    my ($self, $scope, $hash) = @_;
    $self->{_mock_configs}{$scope} = $hash;
}

1;

###############################################################################
# MockTemplate
###############################################################################
package MockTemplate;
sub new { bless { name => $_[1] }, $_[0] }
sub name { $_[0]->{name} }
1;

###############################################################################
# MockBlog
###############################################################################
package MockBlog;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub id        { $_[0]->{id} }
sub site_path { $_[0]->{site_path} || '/var/www/html' }

sub parent {
    return $_[0]->{parent};
}

sub is_blog {
    return $_[0]->{is_blog} // 1;
}

sub website {
    return $_[0]->{website};
}

sub can {
    my ($self, $method) = @_;
    # Allow SUPER::can for real methods
    return $self->SUPER::can($method) if @_ == 1;
    # For specific method name checks
    if ($method eq 'parent')  { return exists $self->{parent}  ? 1 : 1 }
    if ($method eq 'website') { return exists $self->{website} ? 1 : 0 }
    if ($method eq 'is_blog') { return 1 }
    return $self->SUPER::can($method);
}

# Mock load class method
my $_blog_store = {};

sub load {
    my ($class_or_self, $id) = @_;
    return $_blog_store->{$id};
}

sub _register {
    my ($class, $blog) = @_;
    $_blog_store->{$blog->id} = $blog;
}

sub _clear_all {
    $_blog_store = {};
}

1;

###############################################################################
# MockAuthor
###############################################################################
package MockAuthor;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub is_superuser { $_[0]->{is_superuser} || 0 }

sub permissions {
    my ($self, $blog_id) = @_;
    return $self->{_permissions}{$blog_id};
}

1;

###############################################################################
# MockPermission
###############################################################################
package MockPermission;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub can_do {
    my ($self, $action) = @_;
    return $self->{_can_do}{$action} || 0;
}

sub can_administer { $_[0]->{can_administer} || 0 }

1;

###############################################################################
# MockApp - isa MT::App
###############################################################################
package MT::App;
use strict;
use warnings;

our @ISA = ();

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub blog { $_[0]->{blog} }

sub user { $_[0]->{user} }

sub error {
    my ($self, $msg) = @_;
    $self->{_last_error} = $msg;
    return undef;
}

sub permission_denied {
    my ($self) = @_;
    $self->{_permission_denied} = 1;
    return 'permission_denied';
}

sub build_page {
    my ($self, $tmpl, $param) = @_;
    return { tmpl => $tmpl, param => $param };
}

sub request_method { $_[0]->{request_method} || 'GET' }

sub validate_magic { $_[0]->{_magic_valid} || 0 }

sub current_magic { 'mock_magic_token' }

1;

###############################################################################
# TheSchwartz::Job (mock)
###############################################################################
package TheSchwartz::Job;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        _completed => 0,
        _failed    => undef,
    }, $class;
}

sub funcname {
    my ($self, $val) = @_;
    $self->{funcname} = $val if defined $val;
    return $self->{funcname};
}

sub arg {
    my ($self, $val) = @_;
    $self->{arg} = $val if defined $val;
    return $self->{arg};
}

sub uniqkey {
    my ($self, $val) = @_;
    $self->{uniqkey} = $val if defined $val;
    return $self->{uniqkey};
}

sub coalesce {
    my ($self, $val) = @_;
    $self->{coalesce} = $val if defined $val;
    return $self->{coalesce};
}

sub completed {
    my ($self) = @_;
    $self->{_completed} = 1;
}

sub failed {
    my ($self, $msg) = @_;
    $self->{_failed} = $msg || 1;
}

sub is_completed { $_[0]->{_completed} }
sub failure_msg  { $_[0]->{_failed} }

1;

###############################################################################
# TheSchwartz::Worker (mock base class)
###############################################################################
package TheSchwartz::Worker;
use strict;
use warnings;

1;

###############################################################################
# MT::TheSchwartz (mock)
###############################################################################
package MT::TheSchwartz;
use strict;
use warnings;

my @_inserted_jobs;
my @_coalesced_jobs;
my $_instance;

sub insert {
    my ($class, $job) = @_;
    push @_inserted_jobs, $job;
    return 1;
}

sub instance {
    $_instance ||= bless {}, __PACKAGE__;
    return $_instance;
}

sub find_job_with_coalescing_value {
    my ($self, $class, $key) = @_;
    return shift @_coalesced_jobs;
}

sub _get_inserted_jobs { @_inserted_jobs }
sub _clear_inserted_jobs { @_inserted_jobs = () }
sub _set_coalesced_jobs { shift; @_coalesced_jobs = @_ }
sub _clear_coalesced_jobs { @_coalesced_jobs = () }

1;

###############################################################################
# MT (main mock)
###############################################################################
package MT;
use strict;
use warnings;

my $_mt_instance;
my %_components;
my @_logs;
my %_models;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub instance {
    my ($class_or_self) = @_;
    return $_mt_instance;
}

sub _set_instance {
    my ($class, $inst) = @_;
    $_mt_instance = $inst;
}

sub component {
    my ($class_or_self, $name) = @_;
    return $_components{$name};
}

sub _set_component {
    my ($class, $name, $comp) = @_;
    $_components{$name} = $comp;
}

sub add_plugin {
    my ($class, $plugin) = @_;
    # Register as component so MT->component() returns this plugin
    my $key = $plugin->{key} || $plugin->{name} || '';
    $_components{$key} = $plugin if $key;
}

sub model {
    my ($class_or_self, $name) = @_;
    return $_models{$name} if $_models{$name};
    if ($name eq 'blog') {
        return 'MockBlog';
    }
    return undef;
}

sub _set_model {
    my ($class, $name, $model_class) = @_;
    $_models{$name} = $model_class;
}

sub log {
    my ($class_or_self, $entry) = @_;
    push @_logs, $entry;
}

sub _get_logs { @_logs }
sub _clear_logs { @_logs = () }

sub _reset {
    $_mt_instance = undef;
    %_components = ();
    @_logs = ();
    %_models = ();
    MT::PluginData->_clear_all();
    MT::TheSchwartz->_clear_inserted_jobs();
    MT::TheSchwartz->_clear_coalesced_jobs();
    MockBlog->_clear_all();
}

1;

###############################################################################
# Package init
###############################################################################
package MockMT;
use strict;
use warnings;

sub import {
    # Nothing to do; loading this module defines all mock packages.
}

sub setup_default {
    MT->_reset();

    my $plugin = MT::Plugin->new(
        name => 'AWSUtils',
        key  => 'AWSUtils',
    );
    $plugin->_set_config('system', {
        access_key   => 'AKIAIOSFODNN7EXAMPLE',
        secret_key   => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region       => 'ap-northeast-1',
        awscli_path  => 'aws',
        ec2_volume_id => 'vol-12345678',
    });

    MT->_set_component('AWSUtils', $plugin);

    return $plugin;
}

1;
