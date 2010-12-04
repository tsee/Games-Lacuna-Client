package Games::Lacuna::Client::RPC;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';
use Scalar::Util 'weaken';

use Games::Lacuna::Client;

use URI;
use LWP::UserAgent;
use JSON::RPC::Common;
use JSON::RPC::Common::Marshal::HTTP;
use HTTP::Request;
use HTTP::Response;

our @CARP_NOT = qw(
  Games::Lacuna::Client
  Games::Lacuna::Client::Alliance
  Games::Lacuna::Client::Body
  Games::Lacuna::Client::Buildings
  Games::Lacuna::Client::Empire
  Games::Lacuna::Client::Inbox
  Games::Lacuna::Client::Map
  Games::Lacuna::Client::Stats
);

use Class::XSAccessor {
  getters => [qw(ua marshal)],
};

use Exception::Class (
    'LacunaException',
    'LacunaRPCException' => {
        isa         => 'LacunaException',
        description => 'The RPC service generated an error.',
        fields      => [qw(code text)],
    },
);

sub new {
  my $class = shift;
  my %opt = @_;
  $opt{client} || croak("Need Games::Lacuna::Client");
  
  my $self = bless {
    %opt,
    ua => LWP::UserAgent->new(env_proxy => 1),
    marshal => JSON::RPC::Common::Marshal::HTTP->new,
  } => $class;
  
  weaken($self->{client});
  
  return $self;
}

sub call {
  my $self = shift;
  my $uri = shift;
  my $method = shift;
  my $params = shift;
  
  my $req = $self->marshal->call_to_request(
    JSON::RPC::Common::Procedure::Call->inflate(
      jsonrpc => "2.0",
      id      => "1",
      method  => $method,
      params  => $params,
    ),
    uri => URI->new($uri),
  );
  my $resp = $self->ua->request($req);
  my $res = $self->marshal->response_to_result($resp);

  if ($self->{client}->{verbose_rpc}) {
    my @tmp = @$params;
    shift @tmp;
    printf("RPC: %s(%s)\n",$method,@tmp);
  }
  $self->{client}->{total_calls}++;

  LacunaRPCException->throw(
    error   => "RPC Error (" . $res->error->code . "): " . $res->error->message,
    code    => $res->error->code,
    ## Note we don't use the key 'message'. Exception::Class stringifies based
    ## on "message or error" attribute. For backwards compatiblity we don't
    ## want to change how this object will stringify.
    text    => $res->error->message,
  ) if $res->error;

  return $res->deflate;
}



1;
__END__

=head1 NAME

Games::Lacuna::Client::RPC - The actual RPC client

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 EXCEPTIONS

=head2 LacunaRPCException

This exception is generated if the RPC call fails. It is an Exception::Class object that has the RPC error details.

Attribute C<< $e->code >> contains the error code. Attribute C<< $e->text >> contains the error text.

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
