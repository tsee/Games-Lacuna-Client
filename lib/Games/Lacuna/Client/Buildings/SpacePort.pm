package Games::Lacuna::Client::Buildings::SpacePort;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

our @ISA = qw(Games::Lacuna::Client::Buildings);

sub api_methods {
  return {
    view                    => { default_args => [qw(session_id building_id)] },
    view_all_ships          => { default_args => [qw(session_id building_id)] },
    view_foreign_ships      => { default_args => [qw(session_id building_id)] },
    get_ships_for           => { default_args => [qw(session_id)] },
    send_ship               => { default_args => [qw(session_id)] },
    send_fleet              => { default_args => [qw(session_id)] },
    recall_ship             => { default_args => [qw(session_id building_id)] },
    recall_all              => { default_args => [qw(session_id building_id)] },
    name_ship               => { default_args => [qw(session_id building_id)] },
    scuttle_ship            => { default_args => [qw(session_id building_id)] },
    view_ships_travelling   => { default_args => [qw(session_id building_id)] },
    view_ships_orbiting     => { default_args => [qw(session_id building_id)] },
    prepare_send_spies      => { default_args => [qw(session_id)] },
    send_spies              => { default_args => [qw(session_id)] },
    prepare_fetch_spies     => { default_args => [qw(session_id)] },
    fetch_spies             => { default_args => [qw(session_id)] },
    view_battle_logs        => { default_args => [qw(session_id building_id)] },
  };
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::SpacePort - The Space Port building

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
