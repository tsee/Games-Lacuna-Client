package Games::Lacuna::Client::Buildings::Parliament;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

our @ISA = qw(Games::Lacuna::Client::Buildings);

sub api_methods {
  return {
    view_laws                                         => { default_args => [qw(session_id)] },
    view_propositions                                 => { default_args => [qw(session_id building_id)] },
    get_stars_in_jurisdiction                         => { default_args => [qw(session_id building_id)] },
    get_bodies_for_star_in_jurisdiction               => { default_args => [qw(session_id building_id)] },
    get_mining_platforms_for_asteroid_in_jurisdiction => { default_args => [qw(session_id building_id)] },
    cast_vote                                         => { default_args => [qw(session_id building_id)] },
    propose_writ                                      => { default_args => [qw(session_id building_id)] },
    propose_repeal_law                                => { default_args => [qw(session_id building_id)] },
    propose_transfer_station_ownership                => { default_args => [qw(session_id building_id)] },
    propose_seize_star                                => { default_args => [qw(session_id building_id)] },
    propose_rename_star                               => { default_args => [qw(session_id building_id)] },
    propose_broadcast_on_network19                    => { default_args => [qw(session_id building_id)] },
    propose_rename_asteroid                           => { default_args => [qw(session_id building_id)] },
    propose_rename_uninhabited                        => { default_args => [qw(session_id building_id)] },
    propose_members_only_mining_rights                => { default_args => [qw(session_id building_id)] },
    propose_members_only_colonization                 => { default_args => [qw(session_id building_id)] },
    propose_members_only_stations                     => { default_args => [qw(session_id building_id)] },
    propose_members_only_excavation                   => { default_args => [qw(session_id building_id)] },
    propose_evict_mining_platform                     => { default_args => [qw(session_id building_id)] },
    propose_fire_bfg                                  => { default_args => [qw(session_id building_id)] },
    allow_bhg_by_alliance                             => { default_args => [qw(session_id building_id)] },
  };
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Parliament - Parliament

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Carl Franks, E<lt>cfranks@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Carl Franks

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
