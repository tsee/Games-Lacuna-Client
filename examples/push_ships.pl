#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
use POSIX                 (qw(floor));
my $cfg_file;

if ( @ARGV && $ARGV[0] !~ /^--/) {
	$cfg_file = shift @ARGV;
}
else {
	$cfg_file = 'lacuna.yml';
}

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

my $from;
my $to;
my $push_type;
my $trade_type;
my $min_push = 1;
my $fastest;

GetOptions(
    'from=s' => \$from,
    'to=s'   => \$to,
    'push_type=s'  => \$push_type,
    'trade_type=s' => \$trade_type,
    'min_push=i'   => \$min_push,
    'fastest'      => \$fastest,
);

usage() if !$from || !$to || !$push_type;


my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# reverse hash, to key by name instead of id
my %planets_by_name = reverse %$planets;

my $to_id = $planets_by_name{$to}
    or die "--to planet not found";

# Load planet data
my $body      = $client->body( id => $planets_by_name{$from} );
my $buildings = $body->get_buildings->{buildings};

# Check dock space on target planet
my $to_dock_count;
{
    my $to_body      = $client->body( id => $planets_by_name{$to} );
    my $to_buildings = $to_body->get_buildings->{buildings};

    my $space_port_id = first {
        $to_buildings->{$_}->{url} eq '/spaceport'
    }
      grep { $to_buildings->{$_}->{level} > 0 and $to_buildings->{$_}->{efficiency} == 100 }
      keys %$to_buildings;

    die "No spaceport found on target planet\n"
        if !$space_port_id;

    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

    $to_dock_count = $space_port->view->{docks_available};

    die "No docks available in target SpacePort\n"
        if !$to_dock_count;
}

die "Fewer free docks in target SpacePort than --min_push value\n"
    if $min_push > $to_dock_count;

# Find the TradeMin
my $trade_min_id = first {
        $buildings->{$_}->{name} eq 'Trade Ministry'
} keys %$buildings;

my $trade_min = $client->building( id => $trade_min_id, type => 'Trade' );

my @trade_ships = @{ $trade_min->get_trade_ships($to_id)->{ships} };

if ($trade_type) {

    @trade_ships = grep {
        $_->{type} =~ m/$trade_type/
    } @trade_ships;

}

my $get_ships_result = $trade_min->get_ships;

my $hold_required = $get_ships_result->{cargo_space_used_each};

@trade_ships = grep {
    $_->{hold_size} >= $min_push*$hold_required;
} @trade_ships;

die "No available ships to push with"
    if !@trade_ships;

@trade_ships = sort {
    $fastest ? $b->{speed} <=> $a->{speed} : $b->{hold_size} <=> $a->{hold_size}
} @trade_ships;

my @push_ships = @{ $get_ships_result->{ships} };

@push_ships = grep {
    $_->{type} =~ m/$push_type/;
} @push_ships;

die "No ships available to be pushed\n"
    if !@push_ships;

die "Less than --min_push ships available to be pushed\n"
    if $min_push > scalar @push_ships;

for my $trade_ship (@trade_ships) {
    last if $min_push > scalar @push_ships;
    last if $min_push > $to_dock_count;
    last if $to_dock_count < 1;

    my $max_ships = floor( $trade_ship->{hold_size} / $hold_required );

    my $ship_count = $max_ships > scalar @push_ships ? scalar @push_ships
                   :                                   $max_ships;

    $ship_count = $to_dock_count
        if $ship_count > $to_dock_count;

    my @push_ships = splice @push_ships, 0, $ship_count;

    my @items;

    for my $push_ship (@push_ships) {
        push @items, {
            type    => 'ship',
            ship_id => $push_ship->{id},
        };
    }

    my $return = $trade_min->push_items(
        $to_id,
        \@items,
        {
            ship_id => $trade_ship->{id},
        },
    );

    printf "Pushed %s\n", join ',', map {"'$_'"} map { $_->{name} } @push_ships;
    printf "Using '%s', arriving %s\n", $return->{ship}{name}, $return->{ship}{date_arrives};

    $to_dock_count -= $ship_count;
}


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --from      PLANET_NAME
       --to        PLANET_NAME
       --push_type SHIP_TYPE
       --trade_type  SHIP_TYPE
       --min_push  MIN_PUSH
       --fastest
       --largest

CONFIG_FILE  defaults to 'lacuna.yml'

--push_type SHIP_TYPE is a regex used to decide which ships to push. Required.
If this is set to a trade-type ship, then you must also set --trade_type to a
different type of ship, so that a ship doesn't try pushing itself.

--trade_type SHIP_TYPE is a regex used to decide which ships to use to push the
selected ships.
By default, is not set, so all trade ships are candidates.

MIN_PUSH is the minimum number of matching ships that are required per-push.
Each pushing-ship requires a 50K cargo-hold per ship being pushed.
Defaults to 1, so any trade ship above 50K is a candidate.

--fastest or --largest may be set, to decide which ships to use to push.
If neither is set, --largest will be the default behaviour.

END_USAGE

}

