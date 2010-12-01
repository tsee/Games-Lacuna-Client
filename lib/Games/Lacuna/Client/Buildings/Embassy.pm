package Games::Lacuna::Client::Buildings::Embassy;
use 5.0080000;
use strict;
use Carp 'croak';
use warnings;

use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

our @ISA = qw(Games::Lacuna::Client::Buildings);

sub api_methods {
  return {
    view                   => { default_args => [qw(session_id building_id)] },
    create_alliance        => { default_args => [qw(session_id building_id)] },
    dissolve_alliance      => { default_args => [qw(session_id building_id)] },
    get_alliance_status    => { default_args => [qw(session_id building_id)] },
    send_invite            => { default_args => [qw(session_id building_id)] },
    withdraw_invite        => { default_args => [qw(session_id building_id)] },
    accept_invite          => { default_args => [qw(session_id building_id)] },
    reject_invite          => { default_args => [qw(session_id building_id)] },
    get_pending_invites    => { default_args => [qw(session_id building_id)] },
    get_my_invites         => { default_args => [qw(session_id building_id)] },
    assign_alliance_leader => { default_args => [qw(session_id building_id)] },
    update_alliance        => { default_args => [qw(session_id building_id)] },
    leave_alliance         => { default_args => [qw(session_id building_id)] },
    expel_member           => { default_args => [qw(session_id building_id)] },
    view_stash             => { default_args => [qw(session_id building_id)] },
    donate_to_stash        => { default_args => [qw(session_id building_id)] },
    exchange_with_stash    => { default_args => [qw(session_id building_id)] },

  };
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Embassy - The Embassy building

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
