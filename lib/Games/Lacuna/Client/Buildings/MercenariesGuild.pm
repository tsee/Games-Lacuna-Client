package Games::Lacuna::Client::Buildings::MercenariesGuild;
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
    get_spies             => { default_args => [qw(session_id building_id)] },
    withdraw_from_market  => { default_args => [qw(session_id building_id)] },
    accept_from_market    => { default_args => [qw(session_id building_id)] },
    view_market           => { default_args => [qw(session_id building_id)] },
    view_my_market        => { default_args => [qw(session_id building_id)] },
    get_trade_ships       => { default_args => [qw(session_id building_id)] },
    report_abuse          => { default_args => [qw(session_id building_id)] },
  };
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::MercenariesGuild - The Mercenaries Guild building

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Carl Franks, E<lt>cfranks@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
