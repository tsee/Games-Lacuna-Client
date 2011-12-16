#!/usr/bin/perl

use strict;
use warnings;
use Clone        qw(clone);
use List::Util   qw(first max);
use Getopt::Long qw(GetOptions);
use YAML::Any    qw( LoadFile );

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

$| = 1;
my $build_gap = 3; # seconds

# if there is only 1 arg, assume it's the build_plan.yml for later, not this config
my $cfg_file = @ARGV == 2 ? shift @ARGV : 'lacuna.yml';
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
    usage( "Did not provide a config file" );
  }
}

my $plan_file = @ARGV ? shift @ARGV : 'build_plan.yml';
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
my %planets = reverse %{ $empire->{planets} };

# Load planet data
my $planet = $client->body( id => $planets{$planet_name} );
my $buildings;
my $dev_min;

print "Planet: $planet_name\n";

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
            grep { defined $item->{upgrade}{x} ? ( $item->{upgrade}{x} eq $buildings->{$_}{x} ) : 1 }
            grep { defined $item->{upgrade}{y} ? ( $item->{upgrade}{y} eq $buildings->{$_}{y} ) : 1 }
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

    if ( my $levels = $item->{levels} ) {
        my $copy = clone( $item );

        delete $copy->{levels};

        if ( $item->{build} ) {
            $copy->{upgrade} = delete $copy->{build};
        }
        else {
            # need to get x,y in case there's another of the same type already built
            my $building = $client->building(
                id   => $return->{building}{id},
                type => $item->{upgrade}{type},
            );

            my $return = $building->view;

            $copy->{upgrade}{x} = $return->{building}{x};
            $copy->{upgrade}{y} = $return->{building}{y};
        }

        # already handled 1
        $levels--;

        for my $level ( 1 .. $levels ) {
            splice @queue, $i+$level, 0, clone( $copy );
        }
    }

    if ( $item->{subsidize} ) {
        my $dev_min = get_dev_min();

        if ( $dev_min ) {
            print "Subsidizing build\n";

            $dev_min->subsidize_build_queue;
            sleep 1;
            next;
        }
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

sub get_dev_min {
    return $dev_min if $dev_min;

    my $id = first {
        $buildings->{$_}{url} eq "/development"
    } keys %$buildings;

    if ( !$id ) {
        warn "Cannot subsidize without a Development Ministry\n";
        return;
    }

    return $client->building( id => $id, type => "Development" );
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
