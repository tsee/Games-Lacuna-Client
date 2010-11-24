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

    sub can_party {
        my $class = shift;
        my $gov   = shift;
        my $park  = shift;
        return 1 if $gov->building_details($gov->{current}{planet_id}, $park->{building_id})->{party}{can_throw};
        trace( sprintf "There is already a party in progress in park[%i]", $park->{building_id} );
        return;
    }

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

    sub should_party {
        my $class   = shift;
        my $gov     = shift;
        my $park    = shift;
        my $trade   = shift;
        my ($pid, $config, $status)  = @{$gov->{current}}{qw(planet_id config status)};
        my $pname   = $gov->{planet_names}{$pid};

        my $food_limit = ($config->{profile}{food}{build_above} || 0) > 0
            ? $config->{profile}{food}{build_above}
            : $config->{profile}{_default_}{build_above};

        my $stored_food = $status->{food_stored};
        return $stored_food - $PARTY_COST >= $food_limit;
    }

}

1;
__END__
=pod

=cut


