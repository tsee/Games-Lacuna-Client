package Games::Lacuna::Client::Buildings::Transporter;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

our @ISA = qw(Games::Lacuna::Client::Buildings);

sub api_methods {
  return {
    add_to_market         => { default_args => [qw(session_id building_id)] },
    get_ships             => { default_args => [qw(session_id building_id)] },
    get_prisoners         => { default_args => [qw(session_id building_id)] },
    get_plans             => { default_args => [qw(session_id building_id)] },
    get_glyphs            => { default_args => [qw(session_id building_id)] },
    withdraw_from_market  => { default_args => [qw(session_id building_id)] },
    accept_from_market    => { default_args => [qw(session_id building_id)] },
    view_market           => { default_args => [qw(session_id building_id)] },
    view_my_market        => { default_args => [qw(session_id building_id)] },
    get_trade_ships       => { default_args => [qw(session_id building_id)] },
    get_stored_resources  => { default_args => [qw(session_id building_id)] },
    push_items            => { default_args => [qw(session_id building_id)] },
    trade_one_for_one     => { default_args => [qw(session_id building_id)] },
    report_abuse          => { default_args => [qw(session_id building_id)] },
    
    # deprecated - old trade system
    add_trade             => { default_args => [qw(session_id building_id)] },
    withdraw_trade        => { default_args => [qw(session_id building_id)] },
    accept_trade          => { default_args => [qw(session_id building_id)] },
    view_available_trades => { default_args => [qw(session_id building_id)] },
    view_my_trades        => { default_args => [qw(session_id building_id)] },
  };
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Transporter - The Subspace Transporter building

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
