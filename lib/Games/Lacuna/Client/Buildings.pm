package Games::Lacuna::Client::Buildings;
use 5.010000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
our @ISA = qw(Games::Lacuna::Client::Module);

require Games::Lacuna::Client::Buildings::Simple;

require Games::Lacuna::Client::Buildings::Archeology;
require Games::Lacuna::Client::Buildings::Development;
require Games::Lacuna::Client::Buildings::Embassy;
require Games::Lacuna::Client::Buildings::Intelligence;
require Games::Lacuna::Client::Buildings::Mining;
require Games::Lacuna::Client::Buildings::Network19;
require Games::Lacuna::Client::Buildings::Observatory;
require Games::Lacuna::Client::Buildings::Park;
require Games::Lacuna::Client::Buildings::PlanetaryCommand;
require Games::Lacuna::Client::Buildings::Security;
require Games::Lacuna::Client::Buildings::Shipyard;
require Games::Lacuna::Client::Buildings::SpacePort;
require Games::Lacuna::Client::Buildings::Trade;
require Games::Lacuna::Client::Buildings::Transporter;
require Games::Lacuna::Client::Buildings::WasteRecycling;

use Class::XSAccessor {
  getters => [qw(building_id)],
};

sub api_methods {
  return {
    build               => { default_args => [qw(session_id)] },
    view                => { default_args => [qw(session_id building_id)] },
    upgrade             => { default_args => [qw(session_id building_id)] },
    demolish            => { default_args => [qw(session_id building_id)] },
    downgrade           => { default_args => [qw(session_id building_id)] },
    get_stats_for_level => { default_args => [qw(session_id building_id)] },
    repair              => { default_args => [qw(session_id building_id)] },
  };
}

sub new {
  my $class = shift;
  $class = ref($class)||$class; # no cloning
  my %opt = @_;
  my $btype = delete $opt{type};
  
  # redispatch in factory mode
  if (defined $btype) {
    if ($class ne 'Games::Lacuna::Client::Buildings') {
      croak("Cannot call ->new on Games::Lacuna::Client::Buildings subclass ($class) and pass the 'type' parameter");
    }
    my $realclass = "Games::Lacuna::Client::Buildings::$btype";
    return $realclass->new(%opt);
  }
  my $id = delete $opt{id};
  my $self = $class->SUPER::new(%opt);
  $self->{building_id} = $id;
  # We could easily support the body_id as default argument for ->build
  # here, but that would mean you had to specify the body_id at build time
  # or require building construction via $body->building(...)
  # Let's keep it simple for now.
  #$self->{body_id} = $opt{body_id};
  
  bless $self => $class;
  return $self;
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings - The buildings module

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
