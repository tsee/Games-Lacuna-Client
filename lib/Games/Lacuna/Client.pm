package Games::Lacuna::Client;
use 5.010000;
use strict;
use warnings;
use Carp 'croak';

our $VERSION = '0.01';
use constant DEBUG => 1;

use Games::Lacuna::Client::Module; # base module class
use Data::Dumper ();

#our @ISA = qw(JSON::RPC::Client);
use Class::XSAccessor {
  getters => [qw(
    rpc
    uri name password api_key
  )],
  accessors => [qw(
    debug
    session_id
    session_start
    session_timeout
  )],
};

require Games::Lacuna::Client::RPC;

require Games::Lacuna::Client::Alliance;
require Games::Lacuna::Client::Body;
require Games::Lacuna::Client::Buildings;
require Games::Lacuna::Client::Empire;
require Games::Lacuna::Client::Inbox;
require Games::Lacuna::Client::Map;
require Games::Lacuna::Client::Stats;


sub new {
  my $class = shift;
  my %opt = @_;
  my @req = qw(uri name password api_key);
  croak("Need the following parameters: @req")
    if not exists $opt{uri}
       or not exists $opt{name}
       or not exists $opt{password}
       or not exists $opt{api_key};
  $opt{uri} =~ s/\/+$//;
  
  my $self = bless {
    session_start   => 0,
    session_id      => 0,
    session_timeout => 3600*1.5, # server says it's 2h, but let's play it safe.
    debug           => 0,
    %opt
  } => $class;
  
  # the actual RPC client
  $self->{rpc} = Games::Lacuna::Client::RPC->new(client => $self);

  return $self,
}

sub empire {
  my $self = shift;
  return Games::Lacuna::Client::Empire->new(client => $self, @_);
}

sub alliance {
  my $self = shift;
  return Games::Lacuna::Client::Alliance->new(client => $self, @_);
}

sub body {
  my $self = shift;
  return Games::Lacuna::Client::Body->new(client => $self, @_);
}

sub building {
  my $self = shift;
  return Games::Lacuna::Client::Buildings->new(client => $self, @_);
}

sub inbox {
  my $self = shift;
  return Games::Lacuna::Client::Inbox->new(client => $self, @_);
}

sub map {
  my $self = shift;
  return Games::Lacuna::Client::Map->new(client => $self, @_);
}

sub stats {
  my $self = shift;
  return Games::Lacuna::Client::Stats->new(client => $self, @_);
}


sub DESTROY {
  my $self = shift;
  $self->assert_session;
  $self->empire->logout();
}

sub assert_session {
  my $self = shift;
  
  my $now = time();
  if (!$self->session_id || $now - $self->session_start > $self->session_timeout) {
    if ($self->debug) {
      print "DEBUG: Logging in since there is no session id or it timed out.\n";
    }
    my $res = $self->empire->login($self->{name}, $self->{password}, $self->{api_key});
    $self->{session_id} = $res->{session_id};
    if ($self->debug) {
      print "DEBUG: Set session id to $self->{session_id} and updated session start time.\n";
    }
  }
  elsif ($self->debug) {
      print "DEBUG: Using existing session.\n";
  }
  $self->{session_start} = $now; # update timeout
  return $self->session_id;
}


1;
__END__

=head1 NAME

Games::Lacuna::Client - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Games::Lacuna::Client;
  my $client = Games::Lacuna::Client->new(
    uri      => 'https://path/to/server',
    api_key  => 'your api key here',
    name     => 'empire name',
    password => 'sekrit',
    #debug    => 1,
  );
  
  my $res = $client->alliance->find("The Understanding");
  my $id = $res->{alliances}->[0]->{id};
  
  use Data::Dumper;
  print Dumper $client->alliance->view_profile( $res->{alliances}->[0]->{id} );

=head1 DESCRIPTION

This module implements the Lacuna Expanse API as of 6.10.2010.

The different API I<modules> are available by calling the respective
module name as a method on the client object. The returned object then
implements the various methods.

The return values of the methods are (currently) just exactly C<result> portion
of the deflated JSON responses. This is subject to change!

On failure, the methods C<croak> with a simple to parse message.
Example:

  RPC Error (1002): Empire does not exist. at ...

The number is the error code number (see API docs). The text after the colon
is the human-readable error message from the server.

You do not need to login explicitly. The client will do this on demand. It will
also handle session-timeouts and logging out for you. (Log out happens in the
destructor.)

All methods that take a session id as first argument in the
JSON-RPC API B<DO NOT REQUIRE> that you pass the session_id
manually. This is handled internally and the client will
automatically log in for you as necessary.

=head1 SEE ALSO

API docs at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
