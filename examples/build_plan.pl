#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();
use YAML::Any             qw( LoadFile );

$| = 1;
my $build_gap = 5; # seconds

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	usage( "Did not provide a config file" );
}

my $plan_file = shift(@ARGV) || 'build_plan.yml';
unless ( $plan_file and -e $plan_file ) {
	usage( "Did not provide a plan file" );
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the plan
my $plan_config = LoadFile( $plan_file );
my $planet_name = $plan_config->{planet}
    or usage( "planet name missing" );

my @queue = @{ $plan_config->{queue} };

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Load planet data
my $planet = $client->body( id => $planets{$planet_name} );
my $buildings;

# run through our queue
for (my $i = 0; $i <= $#queue; $i++) {
    my $item = $queue[$i];
    my $return;
    
    # wait if there's something already in / been added to the build queue
    while ( my $pending = build_remaining() ) {
        printf "Already something building: waiting for %d seconds\n", $pending;
        sleep $pending+$build_gap;
    }
    
    if ( $item->{build} ) {
        printf "Building %s at %d,%d\n",
            $item->{build}{type},
            $item->{build}{x},
            $item->{build}{y};
        
        my $building = $client->building( type => $item->{build}{type} );
        $return = $building->build( $planet->{body_id}, $item->{build}{x}, $item->{build}{y} );
    }
    else {
        my $url = lc $item->{upgrade}{type};
        $url = "/$url";
        
        my ($match) =
            grep { $buildings->{$_}{url} eq $url }
            grep { $item->{upgrade}{x} ? ( $item->{upgrade}{x} eq $buildings->{$_}{x} ) : 1 }
            grep { $item->{upgrade}{y} ? ( $item->{upgrade}{y} eq $buildings->{$_}{y} ) : 1 }
            keys %$buildings;
        
        die "building not found: '$url'"
            if !$match;
        
        my $building = $client->building( id => $match, type => $item->{upgrade}{type} );
        
        printf  "Upgrading %s at %d,%d\n",
            $item->{upgrade}{type},
            $buildings->{$match}{x},
            $buildings->{$match}{y};
        
        $return = $building->upgrade;
    }
    
    # quit if we're at the end of the queue
    last if !$queue[$i+1];
    
    my $wait = $return->{building}{pending_build}{seconds_remaining};
    
    sleep( $wait+$build_gap );
}

sub build_remaining {
    $buildings = $planet->get_buildings->{buildings};
    
    return
        max
        grep { defined }
        map { $buildings->{$_}{pending_build}{seconds_remaining} }
            keys %$buildings;
}

sub usage {
    my ($message) = @_;
    
    $message = $message ? "$message\n\n" : '';
    
    die <<"END_USAGE";
${message}Usage: $0 CONFIG_FILE BUILD_CONFIG_FILE

CONFIG_FILE defaults to 'lacuna.yml' in the current directory.

BUILD_CONFIG_FILE defaults to 'build_plan.yml' in the current directory.

See the examples/build_plan.yml for an example BUILD_CONFIG_FILE.

TO-DO
=====
Adding checks for resource and waste levels.
Currently it will die if trying to build/upgrade with insufficient resources.
It will also overflow your waste stores with total disregard for hygiene.

END_USAGE

}
