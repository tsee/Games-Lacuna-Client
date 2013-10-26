package Games::Lacuna::Client::RPC;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';
use Scalar::Util 'weaken';
use Time::HiRes qw( sleep );

use Games::Lacuna::Client;

use IO::Interactive qw( is_interactive );

our @CARP_NOT = qw(
  Games::Lacuna::Client
  Games::Lacuna::Client::Alliance
  Games::Lacuna::Client::Body
  Games::Lacuna::Client::Buildings
  Games::Lacuna::Client::Captcha
  Games::Lacuna::Client::Empire
  Games::Lacuna::Client::Inbox
  Games::Lacuna::Client::Map
  Games::Lacuna::Client::Stats
);

use Exception::Class (
    'LacunaException',
    'LacunaRPCException' => {
        isa         => 'LacunaException',
        description => 'The RPC service generated an error.',
        fields      => [qw(code text)],
    },
);

use namespace::clean;

use Moose;

extends 'JSON::RPC::LWP';

has client => (
  is => 'ro',
  isa => 'Games::Lacuna::Client',
  required => 1,
  weak_ref => 1,
);

unless( eval{ JSON::RPC::LWP->VERSION(0.007); 1 } ){
  # was always called with ( id => "1" )
  has '+id_generator' => (
    default => sub{sub{1}},
  );
}

around call => sub {
  my $orig = shift;
  my $self = shift;
  my $uri = shift;
  my $method = shift;
  my $params = shift;


    # Call the method.  If a Captcha error is returned, attempt to handle it
    # and re-call the method, up to 3 times
    my $trying           = 1;
    my $is_interactive   = is_interactive();
    my $try_captcha      = $self->{client}->open_captcha || $self->{client}->prompt_captcha;
    my $captcha_attempts = 0;
    my $res;

    while ($trying) {
        $trying = 0;

        $res = $self->$orig($uri,$method,$params);

        # Throttle per 3.0 changes
        sleep($self->{client}->rpc_sleep) if $self->{client}->rpc_sleep;

        if ($res and $res->has_error
            and $res->error->code eq '1016'
            and $is_interactive
            and $try_captcha
            and ++$captcha_attempts <= 3
        ) {
            my $captcha = $self->{client}->captcha;
            my $browser;
            
            if ( $self->{client}->open_captcha ) {
                $browser = $captcha->open_in_browser;
            }
            
            if ( !defined $browser && $self->{client}->prompt_captcha ) {
                $captcha->print_url;
            }
            
            my $answer = $captcha->prompt_for_solution;
            
            $captcha->solve($answer);
            $trying = 1;
        }
     }

     if ($self->{client}->{verbose_rpc}) {
         my @tmp = @$params;
         shift @tmp;
         printf("RPC: %s(%s)\n",$method,@tmp);
     }
     $self->{client}->{total_calls}++;
     $self->{client}{call_stats}{$method}++;

     LacunaRPCException->throw(
         error   => "RPC Error (" . $res->error->code . "): " . $res->error->message,
         code    => $res->error->code,
         ## Note we don't use the key 'message'. Exception::Class stringifies based
         ## on "message or error" attribute. For backwards compatiblity we don't
         ## want to change how this object will stringify.
         text    => $res->error->message,
     ) if $res->error;

     return $res->deflate;
};


no Moose;
__PACKAGE__->meta->make_immutable;
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
