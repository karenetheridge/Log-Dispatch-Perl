package Log::Dispatch::Perl;
use base 'Log::Dispatch::Output';

# Make sure we have version info for this module
# Be strict from now on

$VERSION = '0.03';
use strict;

# Initialize the level name to number conversion
# Initialize the level number to name conversion
# At compile time
#  Set the hashes using a temporary array

my %LEVEL2NUM;
my %NUM2LEVEL;
BEGIN {
    my @level2num = (
     debug      => 0,
     info       => 1,
     notice     => 2,
     warning    => 3,
     error      => 4,
     err        => 4, # MUST be after "error"
     critical   => 5,
     crit       => 5, # MUST be after "critical"
     alert      => 6,
     emergency  => 7,
     emerg      => 7, # MUST be after "emergency"
    );
    %LEVEL2NUM = @level2num;
    %NUM2LEVEL = reverse @level2num; # order fixes double assignments
} #BEGIN

# Initialize the Perl function dispatcher at compile time
# At compile time
#  Set flag whether we have Carp already
#  If a newer version of Perl
#   Set Carp's hash indication which modules not to report

my %ACTION2CODE;
BEGIN {
    my $havecarp = defined $Carp::VERSION;
    unless ($] < 5.008) {
        $Carp::Internal{$_} = 1 foreach ('Log::Dispatch','Log::Dispatch::Output' );
    }

#  Initialize the action to actual code hash

    %ACTION2CODE = (

     ''         => sub { undef },

     carp       => $havecarp ? \&Carp::carp :
                    sub { require Carp;
                          $ACTION2CODE{'carp'} = \&Carp::carp;
                          goto &Carp::carp;
                    },

     cluck      => $] < 5.008 ?
                    sub { $havecarp ||= require Carp;
                          (my $m = Carp::longmess())
                           =~ s#\s+Log::Dispatch::[^\n]+\n##sg;
                          CORE::warn $_[0].$m;
                    } :
                    sub { $havecarp ||= require Carp;
                          CORE::warn $_[0].Carp::longmess();
                    },

     confess    => $] < 5.008 ?
                    sub { $havecarp ||= require Carp;
                          (my $m = Carp::longmess())
                           =~ s#\s+Log::Dispatch::[^\n]+\n##sg;
                          CORE::die $_[0].$m;
                    } :
                    sub { $havecarp ||= require Carp;
                          CORE::die $_[0].Carp::longmess();
                    },

     croak      => $havecarp ? \&Carp::croak :
                    sub {
                        require Carp;
                        $ACTION2CODE{'croak'} = \&Carp::croak;
                        goto &Carp::croak;
                    },

     die        => sub { CORE::die @_ },

     warn       => sub { CORE::warn @_ },
    );
} #BEGIN

# Satisfy require

1;

#---------------------------------------------------------------------------
# new
#
# Required by Log::Dispatch::Output.  Creates a new Log::Dispatch::Perl
# object
#
#  IN: 1 class
#      2..N parameters as a hash

sub new {

# Obtain the parameters
# Create an object
# Do the basic initializations

    my ($class,%p) = @_;
    my $self = bless {},ref $class || $class;
    $self->_basic_init( %p );

# If there are any actions specified
#  For all of the actions specified
#   Initialize number of warnings
#   Convert numeric level to name if it is a number
#   Warn if an unknown level specified
#   Warn if an unknown action specified
#   Set action for this level if no warnings

    my @action;
    if (exists $p{'action'}) {
        while (my ($level,$action) = each %{$p{'action'}}) {
            my $warn;
            $level = $NUM2LEVEL{$level} if exists $NUM2LEVEL{$level};
            warn qq{"$level" is an unknown logging level, ignored\n"}, $warn++
             unless exists $LEVEL2NUM{$level || ''};
            warn qq{"$action" is an unknown Perl action, ignored\n"}, $warn++
             unless exists $ACTION2CODE{$action || ''};
            $action[$LEVEL2NUM{$level}] = $ACTION2CODE{$action || ''}
             unless $warn;
        }
    }

# Set the actions that have not yet been specified

    $action[0] ||= $ACTION2CODE{''};
    $action[1] ||= $ACTION2CODE{''};
    $action[2] ||= $ACTION2CODE{'warn'};
    $action[3] ||= $ACTION2CODE{'warn'};
    $action[4] ||= $ACTION2CODE{'die'};
    $action[5] ||= $ACTION2CODE{'die'};
    $action[6] ||= $ACTION2CODE{'confess'};
    $action[7] ||= $ACTION2CODE{'confess'};

# Save this setting
# Return the instantiated object

    $self->{'action'} = \@action;
    $self;
} #new

#---------------------------------------------------------------------------
# log_message
#
# Required by Log::Dispatch.  Log a single message.
#
#  IN: 1 instantiated Log::Dispatch::Perl object
#      2..N hash with parameters as required by Log::Dispatch

sub log_message {

# Obtain the parameters
# Obtain the level
# Return now unless we know what to do with it

    my ($self,%p) = @_;
    my $level = $p{'level'};
    return unless exists $LEVEL2NUM{$level} or exists $NUM2LEVEL{$level};

# Obtain the level number
# Assume level numeric if not obtained yet (would love to use // here ;-)

    my $num = $LEVEL2NUM{$level};
    $num = $level unless defined $num;

# Obtain the message
# Make sure there's a newline after it
# Set it as _the_ parameter
# Call the appropriate handler on the same level on the stack

    my $message = $p{'message'};
    $message .= "\n" unless substr( $message,-1,1 ) eq "\n";
    @_ = ($message);
    goto &{$self->{'action'}->[$num]};
} #log_message

#---------------------------------------------------------------------------

__END__

=head1 NAME

Log::Dispatch::Perl - Use core Perl functions for logging

=head1 SYNOPSIS

 use Log::Dispatch::Perl ();

 my $dispatcher = Log::Dispatch->new;
 $dispatcher->add( Log::Dispatch::Perl->new(
  name      => 'foo',
  min_level => 'info',
  action    => { debug     => '',
                 info      => '',
                 notice    => 'warn',
                 warning   => 'warn',
                 error     => 'die',
                 critical  => 'die',
                 alert     => 'croak',
                 emergency => 'croak',
               },
 ) );

 $dispatcher->warning( "This is a warning" );

=head1 DESCRIPTION

The "Log::Dispatch::Perl" module offers a logging alternative using standard
Perl core functions.  It allows you to fall back to the common Perl
alternatives for logging, such as "warn" and "cluck".  It also adds the
possibility for a logging action to halt the current environment, such as
with "die" and "croak".

=head1 POSSIBLE ACTIONS

The following actions are currently supported (in alphabetical order):

=head2 (absent or empty string or undef)

Indicates no action should be executed.  Default for log levels "debug" and
"info".

=head2 carp

Indicates a "carp" action should be executed.  See L<Carp/"carp">.  Halts
execution.

=head2 cluck

Indicates a "cluck" action should be executed.  See L<Carp/"cluck">.  Does
B<not> halt execution.

=head2 confess

Indicates a "confess" action should be executed.  See L<Carp/"confess">.  Does
B<not> halt execution.

=head2 croak

Indicates a "croak" action should be executed.  See L<Carp/"croak">.  Halts
execution.

=head2 die

Indicates a "die" action should be executed.  See L<perlfunc/"die">.  Halts
execution.

=head2 warn

Indicates a "warn" action should be executed.  See L<perlfunc/"warn">.  Does
B<not> halt execution.

=head1 REQUIRED MODULES

 Log::Dispatch (1.16)

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2004 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
