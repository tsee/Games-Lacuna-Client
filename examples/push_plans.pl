#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw(first);
use Games::Lacuna::Client ();
use Getopt::Long          qw(GetOptions);
use POSIX                 qw(floor);
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
my $ship_name;
my $match_plan;
my $max;

GetOptions(
    'from=s'  => \$from,
    'to=s'    => \$to,
    'ship=s'  => \$ship_name,
    'plan=s'  => \$match_plan,
    'max=i'   => \$max,
);

usage() if !$from || !$to;


my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# reverse hash, to key by name instead of id
my %planets_by_name = map { $planets->{$_}, $_ } keys %$planets;

my $to_id = $planets_by_name{$to}
    or die "--to planet not found";

# Load planet data
my $body      = $client->body( id => $planets_by_name{$from} );
my $buildings = $body->get_buildings->{buildings};

# Find the TradeMin
my $trade_min_id = first {
        $buildings->{$_}->{name} eq 'Trade Ministry'
} keys %$buildings;

my $trade_min = $client->building( id => $trade_min_id, type => 'Trade' );

my $plans_result = $trade_min->get_plans;
my @plans        = @{ $plans_result->{plans} };

if ( $match_plan ) {
    @plans =
        grep {
            $_->{name} =~ /$match_plan/i
        } @plans;
}

if ( $max && @plans > $max ) {
    splice @plans, $max;
}

if ( !@plans ) {
    print "No plans available to push\n";
    exit;
}

my $ship_id;

if ( $ship_name ) {
    my $ships = $trade_min->get_trade_ships->{ships};
    
    my ($ship) =
        sort {
            $b->{speed} <=> $a->{speed}
        }
        grep {
            $_->{name} =~ /\Q$ship_name/i
        } @$ships;
    
    if ( $ship ) {
        my $cargo_each = $plans_result->{cargo_space_used_each};
        my $cargo_req  = $cargo_each * scalar @plans;
        
        if ( $ship->{hold_size} < $cargo_req ) {
            my $count = floor( $ship->{hold_size} / $cargo_each );
            
            splice @plans, $count;
            
            warn sprintf "Specified ship cannot hold all plans - only pushing %d plans\n", $count;
        }
        
        $ship_id = $ship->{id};
    }
    else {
        print "No ship matching '$ship_name' found\n";
        print "will attempt to push without specifying a ship\n";
    }
}

my @items = 
    map {
        +{
            type    => 'plan',
            plan_id => $_->{id},
        }
    } @plans;

my $return = $trade_min->push_items(
    $to_id,
    \@items,
    $ship_id ? { ship_id => $ship_id }
             : ()
);

printf "Pushed %d plans\n", scalar @plans;
printf "Arriving %s\n", $return->{ship}{date_arrives};

exit;

sub usage {
  die <<END_USAGE;
Usage: $0 CONFIG_FILE
       --from      PLANET_NAME    (REQUIRED)
       --to        PLANET_NAME    (REQUIRED)
       --ship      SHIP NAME REGEX
       --plan      PLAN NAME REGEX
       --max       MAX No. PLANS TO PUSH

CONFIG_FILE  defaults to 'lacuna.yml'

Pushes plans between your own planets.

END_USAGE

}

