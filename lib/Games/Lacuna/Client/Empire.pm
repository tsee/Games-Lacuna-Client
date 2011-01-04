package Games::Lacuna::Client::Empire;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
our @ISA = qw(Games::Lacuna::Client::Module);


use Class::XSAccessor {
  getters => [qw(empire_id)],
};

sub api_methods {
  return {
    (
      map {
        ($_ => { default_args => [qw()] })
      }
      qw( login
          is_name_available
          fetch_captcha
          send_password_reset_message
          reset_password
          get_species_templates
      )
    ),
    found                 => { default_args => [qw(empire_id)] },
    update_species        => { default_args => [qw(empire_id)] },
    invite_friend         => { default_args => [qw(session_id)] },
    change_password       => { default_args => [qw(session_id)] },
    logout                => { default_args => [qw(session_id)] },
    get_status            => { default_args => [qw(session_id)] },
    view_profile          => { default_args => [qw(session_id)] },
    edit_profile          => { default_args => [qw(session_id)] },
    view_public_profile   => { default_args => [qw(session_id)] },
    find                  => { default_args => [qw(session_id)] },
    set_status_message    => { default_args => [qw(session_id)] },
    view_boosts           => { default_args => [qw(session_id)] },
    boost_storage         => { default_args => [qw(session_id)] },
    boost_food            => { default_args => [qw(session_id)] },
    boost_water           => { default_args => [qw(session_id)] },
    boost_energy          => { default_args => [qw(session_id)] },
    boost_ore             => { default_args => [qw(session_id)] },
    boost_happiness       => { default_args => [qw(session_id)] },
    enable_self_destruct  => { default_args => [qw(session_id)] },
    disable_self_destruct => { default_args => [qw(session_id)] },
    redeem_essentia_code  => { default_args => [qw(session_id)] },
    redefine_species_limits => { default_args => [qw(session_id)] },
    redefine_species        => { default_args => [qw(session_id)] },
    view_species_stats    => { default_args => [qw(session_id)] },
  };
}

sub new {
  my $class = shift;
  my %opt = @_;
  my $self = $class->SUPER::new(@_);
  bless $self => $class;
  $self->{empire_id} = $opt{id};
  return $self;
}


sub logout {
  my $self = shift;
  my $client = $self->client;
  if (not $client->session_id) {
    return 0;
  }
  else {
    my $res = $self->_logout;
    return delete $client->{session_id};
  }
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Empire - The empire module

=head1 SYNOPSIS

  use Games::Lacuna::Client;
  use Games::Lacuna::Client::Empire;
  
  my $client = Games::Lacuna::Client->new(...);
  my $empire = $client->empire;
  
  my $status = $empire->get_status;

=head1 DESCRIPTION

A subclass of L<Games::Lacuna::Client::Module>.

=head2 new

Creates an object locally, does not connect to the server.

  Games::Lacuna::Client::Empire->new(client => $client, @parameters);

The $client is a C<Games::Lacuna::Client> object.

Usually, you can just use the C<empire> factory method of the
client object instead:

  my $empire = $client->empire(@parameters); # client set automatically

Optional parameters:

  id => "The id of the empire"

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
