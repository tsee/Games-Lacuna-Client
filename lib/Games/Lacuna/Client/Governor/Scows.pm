#
#===============================================================================
#
#  DESCRIPTION:  Scows.pm sends any available scows to a body's nearest star
#                if waste level exceeeds the colony's 'send_scows_above'
#                configuration for waste.
#
#===============================================================================

package Games::Lacuna::Client::Governor::Scows;
use strict;
use warnings qw(FATAL all);
use Carp;
use English qw(-no_match_vars);
use Data::Dumper;

{
    use Storable qw(lock_nstore lock_retrieve);
    use Date::Parse qw(str2time);
    use List::MoreUtils qw(minmax uniq any);
    use Games::Lacuna::Client::PrettyPrint qw(trace message warning action ptime phours);
    my $PROBES_PER_PAGE = 25;
    my $SHIPS_PER_PAGE = 25;
    my $PROBES_PER_LVL = 3;

    sub run {
        my $class   = shift;
        my $gov     = shift;
        my ($pid,$config,$status) = @{$gov->{current}}{qw(planet_id config status)};

        my $ssa = $config->{profile}->{waste}->{send_scows_above};
        return if (not defined $ssa or
            $status->{waste_capacity} == 0 or
            ($status->{waste_stored}/$status->{waste_capacity}) < $ssa);

        ### Find Spaceports.
        my ($sp) = $gov->find_buildings('SpacePort');
        my @ships;
        my @probe_to_port;
        my $page = 0;
        while( $page <= 4 ){
            $page++;
            my $data = $sp->view_all_ships($page);
            push @ships, grep { $_->{task} eq 'Docked' and $_->{type} eq 'scow' } @{$data->{ships}};
            last if $page * $SHIPS_PER_PAGE >= $data->{number_of_ships};
        }

        my $target = {
            star_id   => $status->{star_id},
        };

        while(@ships &&
            ($status->{waste_stored}/$status->{waste_capacity}) >= $ssa) {
            my $ship = pop @ships;
            $sp->send_ship($ship->{id},$target);
            $status->{waste_stored} -= $ship->{hold_size};
            action('Sending scow from '.$status->{name}.' to star carrying '.$ship->{hold_size}.' waste.');
        }

        return;
    }

}

1;
__END__
=pod

=head1 NAME

Games::Lacuna::Client::Governor::Astronomer - A rudimentary plugin for Governor that will automate the targetting of probes.

=head1 SYNOPSIS

    Add 'astronomer' to the Governor configuration priorities list.

=head1 DESCRIPTION

This module examines each colony and the scows currently available.

This module looks for the profile->waste->send_scows_above configuration key in the governor config
for each colony.  This number is a decimal between 0 and 1, representing a proportion.
If the proportion of waste to capacity is over this amount, scows are sent to the
nearest star.

=head1 SEE ALSO

L<Games::Lacuna::Client>, by Steffen Mueller on which this module is dependent.

L<Games::Lacuna::Client::Governor>, by Adam Bellaire of which this module is a plugin.

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Adam Bellaire, E<lt>bellaire@ufl.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut


