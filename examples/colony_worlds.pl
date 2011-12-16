#!/usr/bin/perl
#
# Script to find worlds known to you (via observatories) which are uninhabited, habitable, and in
# your range of orbits.  Ranks them and presents a summary view.  The scoring algorithm is very
# simply and probably needs work.
#
# Usage: perl colony_worlds.pl [sort]
#
# [sort] is 'score' by default, may also be 'distance', 'water', 'size'.  Shows in descending order.
#
# Sample output for a planet:
#
# ------------------------------------------------------------------------------
# Somestar 6            [ 123, -116] ( 10)
# Size: 33                   Colony Ship Travel Time:  1.9 hours
# Water: 5700    Short Range Colony Ship Travel Time: 83.7 hours
# ------------------------------------------------------------------------------
#   anthraci    1   bauxite 1700     beryl 1000  chalcopy 2800  chromite    1
#   fluorite    1    galena    1  goethite 2400      gold    1    gypsum 2100
#     halite    1   kerogen    1  magnetit    1   methane    1  monazite    1
#     rutile    1    sulfur    1     trona    1  uraninit    1    zircon    1
# ------------------------------------------------------------------------------
# Score:  18% [Size:  15%, Water:  14%, Ore:  25%]
# ------------------------------------------------------------------------------

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use YAML::Any ();
use List::Util qw/first sum/;
use Data::Dumper;
use Getopt::Long;

my $verbose   = 1;
my $help      = 0;
my $cfg_file  = 'lacuna.yml';
my $cond_file = 'colony_conditions.yml';

GetOptions(
    'cfg=s'       => \$cfg_file,
    'cond_file=s' => \$cond_file,
    "verbose!"    => \$verbose,
    "help"        => \$help,
) or usage();

usage() if $help;

my $sortby = shift(@ARGV) || 'score';
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
  die usage("Did not provide a config file") unless $cfg_file and -e $cfg_file
}
warn "Conditions file '$cond_file' does not exist" unless -e $cond_file;

sub usage
{
    my ($msg) = @_;
    print $msg ? "$0 - $msg\n" : "$0\n";
    print "Options:\n";
    print "\t--cfg=<filename>         Lacuna Config File, see examples/myaccount.yml\n";
    print "\t--cond_file=<filename>   Colony Conditions File\n";
    print "\t--verbose/--no-verbose   Enable/Disables verbose mode\n";
    print "\n";
    exit(1);
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my %building_prereqs=(
	'Munitions Lab' => {
		'Uraninite' => 25,
		'Monazite' => 25,
	},
	'Pilot Training Facility' => {
		'Gold' => 2,
	},
	'Cloaking Lab' => {},
	'Water Reclamation Plant' => {
		'halite' => 9,
		'sulfur' => 9,
	},
	'Fusion Reactor' => {
	        'Galena' => 16,
	        'Halite' => 16,
	},
	'Ore Refinery' => {
	        'Sulfur' => 7,
	        'Fluorite' => 7,
	},
	'Waste Treatment Center L5' => {
		'halite' => 39,
		'sulfur' => 39,
		'trona' => 39,
	}
);

my %food_prereqs = (
    'Beeldeban Herder' => [5,6,'food_ore'], #requires 'Denton Root Patch'
    'Algae Cropper' => '', #any
    'Dairy Farm' => [3,'trona','food_ore'], #requires 'Corn Plantation'
    'Amalgus Bean Plantation' => [4,'food_ore'], #gypsum, sulfur, or monazite
    'Apple Orchard' => [3,'food_ore'],
    'Corn Plantation' => [2,3,'food_ore'],
    'Denton Root Patch' => [5,6,'food_ore'],
    'Lapis Orchard' => [2,'food_ore'],
    'Malcud Fungus Farm' => '',
    'Potato Patch' => [3,4,'food_ore'],
    'Wheat Farm' => [2,3,4,'food_ore'],
); #max 7
my $max_basic_food_buildings = 7;
my @food_ore=qw/gypsum sulfur monazite/;
sub food_count {
    my $planet = shift;
    my $food_count=0;
    my $planet_orbit = $planet->{orbit};
    FOOD_BUILDING: while (my ($building, $prereqs) = each %food_prereqs) {
        if ($prereqs ne '') {
            my $orbit_found;
            foreach my $pr (@$prereqs) {
                if ($pr =~ /^\d$/) {
                    if ($pr == $planet_orbit) {
                        $orbit_found++;
                    }
                } else {
                    my @ores;
                    if ($pr eq 'food_ore') {
                        @ores=@food_ore;
                    } else {
                        @ores=($pr);
                    }
                    unless (grep { die "no ore $_ on planet ".$planet->{name} unless exists $planet->{ore}{lc $_}; $planet->{ore}{lc $_} > 1 } @ores) {
                        next FOOD_BUILDING;
                    }
                }
            }
            next FOOD_BUILDING unless $orbit_found;
        }
        $food_count++;
    }
    return $food_count;
}

my $conditions={};
my @buildings;
if (-e $cond_file) {
    $conditions=YAML::Any::LoadFile($cond_file);
    if (exists $conditions->{'sort'}) {
        $sortby=$conditions->{'sort'};
    }
    if (exists $conditions->{'buildings'}) {
        foreach my $building (@{$conditions->{'buildings'}}) {
            die "Building '$building' not found in list" if !exists $building_prereqs{$building};
            next if $building_prereqs{$building} eq '' || keys %{$building_prereqs{$building}} == 0;
            push @buildings, $building;
        }
    }
}

my $data = $client->empire->view_species_stats();

# Get orbits
my $min_orbit = $data->{species}->{min_orbit};
my $max_orbit = $data->{species}->{max_orbit};

# Get planets
my $planets        = $data->{status}->{empire}->{planets};
my $home_planet_id = $data->{status}->{empire}->{home_planet_id};
my ($hx,$hy)       = @{$client->body(id => $home_planet_id)->get_status()->{body}}{'x','y'};

# Get obervatories;
my @observatories;
for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    push @observatories, grep { $buildings->{$_}->{url} eq '/observatory' } keys %$buildings;
}

print "Orbits: $min_orbit through $max_orbit\n";
print "Observatory IDs: ".join(q{, },@observatories)."\n";

# Find stars
my @stars;
for my $obs_id (@observatories) {
    push @stars, @{$client->building( id => $obs_id, type => 'Observatory' )->get_probed_stars()->{stars}};
}

# Gather planet data
my @planets;
for my $star (@stars) {
    if ($conditions->{'max_star_distance'}) {
        die "no distance data for star" unless exists $star->{x};
        my $dist = distance($hx,$hy,$star->{x},$star->{y});
        if ( $dist > $conditions->{'max_star_distance'}) {
            if ($verbose) {
                print $star->{name}," is too far from home planet - $dist ly\n";
            }
            next;
        }
    }

    push @planets, grep {
		not defined $_->{empire} && $_->{orbit} >= $min_orbit && $_->{orbit} <= $max_orbit &&
		( $_->{type} eq 'habitable planet' || $conditions->{'gas_giant'} && $_->{type} eq 'gas giant' )
	} @{$star->{bodies}};
}

my $factors_sum=0;

unless (exists $conditions->{'score_factors'}) {
    $conditions->{'score_factors'} = {water_score=>1,size_score=>1,ore_score=>1,food_score=>0.5};
}
my $factors = $conditions->{'score_factors'};
$factors_sum = sum(values %$factors);

sub calculate_score {
    my $planet = shift;
    my $sum=0;
    while ( my ($factor,$factor_weight)=each %$factors) {
        $sum += $planet->{$factor} * $factor_weight;
    }
    return $sum / $factors_sum;
}

sub distance {
    my ($x1,$y1,$x2,$y2) = @_;
    sqrt(($x1 - $x2)**2 + ($y1 - $y2)**2);
}

# Calculate some planet metadata
for my $p (@planets) {
    $p->{distance} = distance($hx,$hy,$p->{x},$p->{y});
    $p->{water_score} = ($p->{water} - 5000) / 50;
    $p->{size_score}  = (($p->{size} > 50 ? 50 : $p->{size} ) - 30) * 5;
    $p->{ore_score}   = (scalar grep { $p->{ore}->{$_} > 1 } keys %{$p->{ore}}) * 5;
    $p->{food_score}   = food_count($p)*100/$max_basic_food_buildings;

    $p->{score}       = calculate_score($p);
}

# Sort and print results
{
    my $count = 0;
    my $limit = $conditions->{limit} || 255;


PLANET: for my $p (sort { $b->{$sortby} <=> $a->{$sortby} } @planets) {
        foreach my $building (@buildings) {
            my $prereqs=$building_prereqs{$building};
            my $ore_available=0;
            while (my ($ore, $quantity) = each %$prereqs) {
                $ore_available++ if ($p->{ore}{lc $ore} >= $quantity);
            }
            next PLANET unless $ore_available;
        }
        my $d = $p->{distance};
        print_bar();
        printf "%-20s [%4s,%4s] (Distance: %3s)\nSize: %2d                   Colony Ship Travel Time:  %3.1f hours\nWater: %4d    Short Range Colony Ship Travel Time: %3.1f hours\n",
            $p->{name},$p->{x},$p->{y},int($d),$p->{size},($d/5.23),$p->{water},($d/.12);
        print_bar();
        for my $ore (sort keys %{$p->{ore}}) {
            printf "  %8s %4d",substr($ore,0,8),$p->{ore}->{$ore};
            if ($ore eq 'chromite' or $ore eq 'gypsum' or $ore eq 'monazite' or $ore eq 'zircon') {
                print "\n";
            }
        }
        print_bar();
        printf "Score: %3d%% [Size: %3d%%, Water: %3d%%, Ore: %3d%%, Food: %3d%%]\n",@{$p}{'score','size_score','water_score','ore_score','food_score'};
        print_bar();
        print "\n";
        last if (++$count >= $limit);
    }
}

sub print_bar {
    print "-" x 78;
    print "\n";
}

