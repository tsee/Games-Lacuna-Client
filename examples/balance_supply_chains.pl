#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Number::Format        qw( format_number );
use List::Util            qw( first max );
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
use Data::Dumper;

my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my @types = qw( food ore water energy waste );

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

$planet_name ||= "Adrvaria";

my $trade;
my $supplies;
my $waste;

foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if defined $planet_name && $planet_name ne $name;

    warn $name;

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    $trade = find_building($buildings, "Trade Ministry");
    $supplies = $trade->view_supply_chains();
    $waste = $trade->view_waste_chains();
}

my $tiers =
{
    "station"   => { lower => 20000, upper => 22000, },
    "low"       => { lower => 400000, upper => 500000, },
    "high"      => { lower => 26000000, upper => 27000000, },
    "default"   => { lower => 50000000, upper => 60000000, },
#    "default"   => { lower => 6000000, upper => 7000000, },
};

my $planet_tiers =
{
#    "Norfolk 6" => "high",
    "Adrvaria Space Station" => "station",
    "UPSSU Outpost" => "station",
#    "Pleunt 5" => "low",
#    "Ous Xyachoo 7" => "low",
#    "Ous Xyachoo 2" => "low",
#    "Marley Camila" => "low",
#    "Baissiaje 4" => "high",
#    "Baissiaje 3" => "high",
#    "Baissiaje 2" => "high",
#    "Baissiaje 5" => "high",
#    "Ketracel 5" => "high",
#    "Acc Eamiepr Egh 1" => "high",
#   "Eern Trooda Ougl 6" => "high",
};

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

#    next if defined $planet_name && $planet_name ne $name;

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}{body};
    my $buildings = $result->{buildings};

    my $tier_name = $planet_tiers->{$name} || "default";
    my $tier = $tiers->{$tier_name};

    my $lower = $tier->{'lower'};
    my $upper = $tier->{'upper'};

    print "$name ($tier_name: $lower < $upper)\n";
    print "=" x length $name;
    print "\n";

    my $max_hour     = max map { length format_number $body->{$_."_hour"} }     @types;
    my $max_stored   = max map { length format_number $body->{$_."_stored"} }   @types;
    my $max_capacity = max map { length format_number $body->{$_."_capacity"} } @types;

    for my $type (@types) {
        printf "%6s: %${max_hour}s/hr - %${max_stored}s / %${max_capacity}s, remaining : %${max_capacity}s",
            ucfirst($type),
            format_number( $body->{$type."_hour"} ),
            format_number( $body->{$type."_stored"} ),
            format_number( $body->{$type."_capacity"} ),
            format_number( $body->{$type."_capacity"} - $body->{$type."_stored"} );

        my $per_hour = $body->{$type."_hour"};
        my $stored = $body->{$type."_stored"};
        my $capacity = $body->{$type."_capacity"};

        my $chain;
        if ($type eq 'waste')
        {
            $chain = $waste->{waste_chain}[0];
        }
        else
        {
            $chain = find_chain($supplies->{supply_chains}, $name, $type);
        }

        unless ($chain)
        {
            print "\n";
            next;
        }

        if ($type ne 'waste')
        {
            my $old_rate = $chain->{resource_hour};
            print "  ($old_rate)\n";

            my $per_hour = $body->{$type."_hour"};
            if ($per_hour < $lower || $per_hour > $upper)
            {
                my $change = ($upper) - $per_hour;
                my $new_rate = $old_rate + $change;
                $new_rate = 0 if ($new_rate < 0);

                if ($new_rate != $old_rate)
                {
                    print "updating $chain->{resource_type} to $name from $old_rate to $new_rate ($change)\n";
                    $trade->update_supply_chain ( $chain->{id}, $chain->{resource_type}, $new_rate);
                }
            }
        }
=cut
        else
        {
            my $old_rate = $chain->{waste_hour};
            print "  ($old_rate)\n";

            if ($old_rate != 0 && ($stored / ($capacity || 1)) < 0.1)
            {
                print "waste below 10%, pausing chain\n";
                $trade->update_waste_chain ( $chain->{id}, 0);
            }
            elsif (($stored / $capacity) > 0.5)
            {
                if ($chain->{percent_transferred} < 100)
                {
                    print " chain full, need more scows\n";
                }

                warn Dumper($chain);
                
                {
                    my $new_rate = ($old_rate * $chain->{percent_transferred}) / 100;
                    warn "$new_rate = ($old_rate * $chain->{percent_transferred}) / 100";
                    my $remaining = $stored / ($new_rate || 1);
                    warn $remaining;

                    $new_rate *= 25 / $remaining  if ($remaining < 25);
                    warn "new: $new_rate";
                    $new_rate = int $new_rate;
                    warn "new: $new_rate";
                    $remaining = $stored / ($new_rate || 1);
                    warn "$remaining = $stored / ($new_rate || 1)";

                    my $change = $new_rate - $old_rate;
                    print "updating waste from $old_rate to $new_rate ($change)\n";
                    print " time to empty: $remaining hours\n";
                    $trade->update_waste_chain ( $chain->{id}, $new_rate);
                }
            }
        }
=cut
    }

    print "\n";
}
use Games::Lacuna::Client::Types;

sub find_chain
{
    my ($chains, $planet_name, $type) = @_;

    my $chain = first
    {
        $_->{body}->{name} eq $planet_name
        && ($_->{resource_type} eq $type
            || ($type eq "ore"  && is_ore_type($_->{resource_type}))
            || ($type eq "food" && is_food_type($_->{resource_type}))
            )
    } @$chains;

    return $chain;
}

=cut
                               'body' => {
                                             'y' => '61',
                                             'name' => 'Ous Xyachoo 7',
                                             'id' => '825250',
                                             'x' => '113',
                                             'image' => 'p8'
                                           },
                                 'percent_transferred' => '116',
                                 'stalled' => '0',
                                 'resource_hour' => '1000000',
                                 'id' => '22378',
                                 'building_id' => '548051',
                                 'resource_type' => 'energy'
                               },

=cut


sub find_building {
    my ($buildings, $name) = @_;

    my $id = first {
        $buildings->{$_}->{name} eq $name
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not $id;
    my $type = Games::Lacuna::Client::Buildings::type_from_url($buildings->{$id}->{url});

    my $building  = $client->building(
        id   => $id,
        type => $type,
    );

    return $building;
}

