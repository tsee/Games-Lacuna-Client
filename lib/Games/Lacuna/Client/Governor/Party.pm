#
#===============================================================================
#
#  DESCRIPTION:  Party throws a party. Figures.
#
#===============================================================================

package Games::Lacuna::Client::Governor::Party;
use strict;
use warnings qw(FATAL all);
use Carp;
use English qw(-no_match_vars);
use Data::Dumper;

{
    use Games::Lacuna::Client::PrettyPrint qw(trace message warning action ptime phours);
    use List::MoreUtils qw(minmax part);
    my $PARTY_COST  = 10_000;
    my $MIN_FOODS   = 3;        # Throwing a party with < 3 foods means negative happiness.

    sub run {
        my $class   = shift;
        my $gov     = shift;
        my ($pid, $status, $cfg) = @{$gov->{current}}{qw(planet_id status config)};
        my $planet_name = $gov->{planet_names}{$pid};

        my (@parks) = $gov->find_buildings('Park');

        if( not @parks ){
            warning(sprintf "There is are no Parks on %s", $planet_name);
            return;
        }

        my ($inactive, $active) = part {
            $gov->building_details($pid, $_->{building_id})->{party}{seconds_remaining} ? 1 : 0;
        } @parks;

        my $dry_run = $gov->{config}{dry_run} ? '[DRYRUN] ' : q{} ;

        ### Start the Party Monster.
        PARK:
        for my $park ( @$inactive ){
            last if $class->check_foods( $gov );
            next if not $class->can_party( $gov, $park );
            next if not $class->should_party( $gov, $park );
            eval {
                if( not $dry_run ){
                    $park->throw_a_party;
                }
                action( sprintf '%sThrowing a party on %s', $dry_run, $planet_name );
            };
            if( my $e = Exception::Class->caught ){
                if( $e->isa("LacunaRPCException") and $e->code == 1011 ){
                    warning(
                        sprintf "Seems we've run out of food! No more parties will be thrown on %s",
                        $planet_name
                    );
                    last PARK;
                }
                $e->rethrow;
            }
        }

        ### If a park is going to finish soon, lets push that as a next_action.
        for my $park ( @parks ){
            my $time = $gov->building_details($pid, $park->{building_id})->{party}{seconds_remaining};
            $gov->set_next_action_if_sooner($time);
        }
    }

    ### Can this Park host a party?
    sub can_party {
        my $class = shift;
        my $gov   = shift;
        my $park  = shift;
        my $bldg  = $park->view;
        return 1 if $bldg->{party}{can_throw};
        trace( sprintf "There is already a party in progress in park[%i]", $park->{building_id} );
        return;
    }

    ### Returns hash of the break-down of food types.
    sub resources {
        my $class   = shift;
        my $gov     = shift;

        my $food_reserve = $gov->{_party}{food_reserve};

        if( my ($trade) = $gov->find_buildings('Trade') ){
            $food_reserve = $trade->get_stored_resources->{resources};
        }
        elsif( my ($reserve) = $gov->find_buildings('FoodReserve') ){
            $food_reserve = $reserve->view->{food_stored};
        }
        return $gov->{_party}{food_reserve} = $food_reserve;
    }

    ### Checks if we have enough food types to run w/o causing negative happiness.
    sub check_foods {
        my $class   = shift;
        my $gov     = shift;
        # To identify food types.
        my $food_resources = $class->resources($gov);

        if( not $food_resources ){
            warning(
                sprintf "%s doesn't have a Trade Ministry or Food Reserve, no parties will be thrown.",
                $gov->{planet_names}{$gov->{current}{planet_id}}
            );
            return 1;
        }

        my $food_cnt = 0;
        $food_cnt++ for grep { ($food_resources->{$_} || 0) > 0 } $gov->food_types;

        return if $food_cnt >= $MIN_FOODS;

        trace(sprintf 'Less than %i food types available, skipping party', $MIN_FOODS);

        return 1;
    }

    ### Checks configuration settings to see if we should run. Things like party_above.
    sub should_party {
        my $class   = shift;
        my $gov     = shift;
        my $park    = shift;
        my $trade   = shift;
        my ($pid, $config, $status)  = @{$gov->{current}}{qw(planet_id config status)};
        my $pname   = $gov->{planet_names}{$pid};

        my $food_limit = $config->{profile}{party_above} || 0;

        my $stored_food = $status->{food_stored};
        return $stored_food - $PARTY_COST >= $food_limit;
    }

}

1;
__END__
=pod

=head1 NAME

Games::Lacuna::Client::Governor::Party - A plugin for Governor that will automate the hosting of Parties.

=head1 SYNOPSIS

    Add 'party' to the Governor configuration priorities list.

=head1 DESCRIPTION

This module examines each colony and hosts a party at each park on it. It will only
execute if a Trade Ministry or Food Reserve is detected as it must verify the
colony has more than 2 food-types. (Less than that will generate negative happiness,
I know this from experience...)

=head2 'party' configuration

This heading contains sub-keys related to parties.
NOTE: C<party> must be a specified item in the priorities list for parties to take place.

=head3 party_above

This is similiar to the C<build_above> setting used in Governor's resource production. This
is the minimum amount of food the colony must maintain if a party is hosted.

=head1 TODO

=head2 Minimum food types

It'd be nice if we had a configuration for how many valid (>500 units) food types must
exist before a party can be hosted.

=head1 SEE ALSO

L<Games::Lacuna::Client>, by Steffen Mueller on which this module is dependent.

L<Games::Lacuna::Client::Governor>, by Adam Bellaire of which this module is a plugin.

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Daniel Kimsey, E<lt>dekimsey@ufl.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut


