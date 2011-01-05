#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first sum));
use Games::Lacuna::Client ();
use Games::Lacuna::Client::Types qw(:resource);
use Getopt::Long          (qw(GetOptions));
use YAML::Any             (qw(LoadFile Dump));
use POSIX                  qw( floor );
my $cfg_file;

if ( @ARGV && $ARGV[0] !~ /^--/) {
	$cfg_file = shift @ARGV;
}
else {
	$cfg_file = 'lacuna.yml';
}

unless ( $cfg_file && -e $cfg_file ) {
    die "config file not found: '$cfg_file'";
}

my $from;
my $to;
my $ship_type  = 'barge|cargo|galleon|freighter';
my $fill_ratio = 0.5;
my $min_level  = 100_000;
my $max_ships;
my $verbose;
my $dryrun;
my $debug;

GetOptions(
    'from=s'       => \$from,
    'to=s'         => \$to,
    'ship_type=s'  => \$ship_type,
    'fill_ratio=s' => \$fill_ratio,
    'min_level=i'  => \$min_level,
    'max_ships=i'  => \$max_ships,
    'verbose'      => \$verbose,
    'dryrun'       => \$dryrun,
    'debug'        => \$debug,
);

usage() if !$from || !$to;


my @foods = food_types;

my @ores = ore_types;


my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# reverse hash, to key by name instead of id
my %planets_by_name = map { $planets->{$_}, $_ } keys %$planets;

my $to_id = $planets_by_name{$to}
    or die "to planet not found";

# Load planet data
my $body      = $client->body( id => $planets_by_name{$from} );
my $result    = $body->get_buildings;
my $buildings = $result->{buildings};

# Find the TradeMin
my $trade_min_id = first {
        $buildings->{$_}->{name} eq 'Trade Ministry'
} keys %$buildings;

my $trade_min = $client->building( id => $trade_min_id, type => 'Trade' );

my @ships = @{ $trade_min->get_trade_ships($to_id)->{ships} };

if ($ship_type) {
    @ships = grep
        {
            $_->{type} =~ m/$ship_type/i;
        }
        @ships;
}

if (!@ships) {
    warn "no suitable ships found\n";
    exit;
}

@ships = sort {
       $b->{hold_size} <=> $a->{hold_size}
    || $b->{speed}     <=> $a->{speed}
    } @ships;

my $resources = $trade_min->get_stored_resources->{resources};

for my $key (@foods, @ores, 'water', 'energy') {
    $resources->{$key} ||= 0;
}

my $ship_count = 1;

for my $ship (@ships) {
    my @items = trade_items( $ship, $resources );
    
    if (!@items) {
        warn "insufficient items to fill ship\n";
        last;
    }
    
    my $return;
    if ( $dryrun ) {
        $return->{ship} = {
            name         => $ship->{name},
            hold_size    => $ship->{hold_size},
            date_arrives => 'DRY RUN',
        };
    }
    else {
        $return = $trade_min->push_items(
            $to_id,
            \@items,
            {
                ship_id => $ship->{id},
            }
        );
    }
    
    printf "Pushed from '%s' to '%s' using '%s' size '%d', arriving '%s'\n",
        $from,
        $to,
        $return->{ship}{name},
        $return->{ship}{hold_size},
        $return->{ship}{date_arrives};
    
    if ($verbose) {
        print Dump(\@items);
    }
    
    last if $max_ships && $ship_count == $max_ships;
    $ship_count++;
}

exit;

sub trade_items {
    my ( $ship, $resources ) = @_;
    
    my ( $food, $ore, $water, $energy ) = resource_totals( $resources );
    
    my $total = sum( $food, $ore, $water, $energy );
    
    my $food_percent   = $food   ? ($food   / $total) : 0;
    my $ore_percent    = $ore    ? ($ore    / $total) : 0;
    my $water_percent  = $water  ? ($water  / $total) : 0;
    my $energy_percent = $energy ? ($energy / $total) : 0;
    
if ($debug) {
    warn <<DEBUG;
  food percent: $food_percent\%
   ore percent: $ore_percent\%
 water percent: $water_percent\%
energy percent: $energy_percent\%
DEBUG
}
    
    my $trade = {};
    my $hold  = $ship->{hold_size};
    
    subtotals( $hold, $trade, $resources, $food_percent,   \@foods    );
    subtotals( $hold, $trade, $resources, $ore_percent,    \@ores     );
    subtotals( $hold, $trade, $resources, $water_percent,  ['water']  );
    subtotals( $hold, $trade, $resources, $energy_percent, ['energy'] );
    
    my $total_trade = sum( values %$trade );
    
if ($debug) {
    warn <<DEBUG;
hold_size: $hold
total resources to push: $total_trade
DEBUG
}
    
    # don't go to zero in any resource
    for my $type ( @foods, @ores, 'water', 'energy' ) {
        
        next if !$trade->{$type};
        
        if ( ( $resources->{$type} - $trade->{$type} ) == 0 ) {
            --$trade->{$type};
        }
    }
    
    if ( ( $total_trade / $hold ) < $fill_ratio ) {
        # ship not full enough
        return;
    }
    
    # new totals for next ship
    map {
        $resources->{$_} -= $trade->{$_}
    }
    @foods, @ores, 'water', 'energy';
    
    return map {
            +{
                type     => $_,
                quantity => $trade->{$_},
            }
        }
        grep {
            $trade->{$_}
        }
        keys %$trade;
}

sub resource_totals {
    my ( $resources ) = @_;
    
    my $food   = sum( @{$resources}{ @foods } );
    my $ore    = sum( @{$resources}{ @ores } );
    my $water  = $resources->{water};
    my $energy = $resources->{energy};
    
    $food   = ( ($food   - $min_level) > 0 ) ? ($food   - $min_level) : 0;
    $ore    = ( ($ore    - $min_level) > 0 ) ? ($ore    - $min_level) : 0;
    $water  = ( ($water  - $min_level) > 0 ) ? ($water  - $min_level) : 0;
    $energy = ( ($energy - $min_level) > 0 ) ? ($energy - $min_level) : 0;
    
    return $food, $ore, $water, $energy;
}

sub subtotals {
    my ( $hold, $trade, $resources, $percent, $types ) = @_;
    
    $hold *= $percent;
    
    my $total_available = sum( @{$resources}{@$types} );
    
    if ( $total_available == 0 ) {
        @{$trade}{@$types} = ( 0 x scalar @$types );
    }
    elsif ( $total_available <= $hold ) {
        @{$trade}{@$types} = @{$resources}{@$types};
    }
    else {
        # more available than the ship can carry
        my $ratio = $hold / $total_available;
        
        @{$trade}{@$types} = map {
            floor( $_ * $ratio )
        } @{$resources}{@$types};
    }
    
    return;
}


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --from       PLANET_NAME
       --to         PLANET_NAME
       --ship_type  SHIP_NAME
       --fill_ratio FILL_RATIO
       --min_level  MIN_LEVEL
       --max_ships  MAX_SHIPS
       --dryrun
       --verbose

Pushes all resources above a configurable level, from one colony to another.
Resources are pushed in proportion to the stored levels.

CONFIG_FILE  defaults to 'lacuna.yml'

SHIP_TYPE is a regex, and defaults to 'barge|cargo|galleon|freighter'

FILL_RATIO defaults to 0.5, meaning a ship is only sent if it can be filled 50%

MIN_LEVEL defaults to 100,000, meaning at least that many units of each of
food, ore, water and energy will be left on the sending planet.

MAX_SHIPS is not set by default. If set, limits the number of ships used to
push resources.

END_USAGE
}

