#!/usr/bin/perl

## Junk building trash removal.
## Will use the highest available junk building (that is not built) to purge.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

my $planet_name;
my $x_loc    = 5;
my $y_loc    = -5;
my $demolish = 1;

GetOptions(
    'planet=s'  => \$planet_name,
    'x=i'       => \$x_loc,
    'y=i'       => \$y_loc,
    'demolish!' => \$demolish,
);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
    $cfg_file = eval {
        require File::HomeDir;
        require File::Spec;
        my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
        File::Spec->catfile( $dist, 'login.yml' ) if $dist;
    };
    unless ( $cfg_file and -e $cfg_file ) {
        die "Did not provide a config file";
    }
}

my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,

    # debug		=> 1,
);

# Load the planets
my $status  = $client->empire->get_status;
my $empire  = $status->{empire};
my $planets = $empire->{planets};

my $available_slots = 0;

if ( $empire->{rpc_count} > ( $status->{server}{rpc_limit} * 0.9 ) ) {
    print "High RPC Count ($empire->{rpc_count}). Exiting.\n";
    exit 1;
}

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if !( $name eq $planet_name );

    print "Checking $x_loc,$y_loc on $name:\n";

    # Load planet data
    my $planet = $client->body( id => $planet_id );
    my $result = $planet->get_buildable( $x_loc, $y_loc, 'Happiness' );
    my $body = $result->{status}->{body};

    my $bb = $result->{buildable};

    my $usebuilding;
    my $buildname;
    foreach my $building ( sort keys %$bb ) {
        my $tagref = $bb->{$building}->{build}->{tags};
        if ( grep( /Now/, @{$tagref} ) ) {
            if ( !defined $usebuilding ) {
                $usebuilding = $bb->{$building};
                $buildname   = $building;
            }
            elsif ( $bb->{$building}->{build}->{cost}->{waste} <
                $usebuilding->{build}->{cost}->{waste} )
            {
                $usebuilding = $bb->{$building};
                $buildname   = $building;
            }
        }
    }

    my $junktype = $buildname;
    $junktype =~ s/ //g;

    if ( grep /Junk/, $buildname ) {
        print "Using $buildname to purge trash\n";
    }
    else {
        die "No junk building available\n";
    }

    my $waste_stored = $body->{waste_stored};
    my $waste_cost   = 0 - $bb->{$buildname}->{build}->{cost}->{waste};

    my $junk = $client->building( type => "$junktype" );

    if ( exists $bb->{$buildname} ) {
        my $last;

        while (1) {
            $waste_stored -= $waste_cost;

            print "$buildname purging $waste_cost trash\n";
            sleep 1;

            my $ok = eval {
                my $return = $junk->build( $planet_id, $x_loc, $y_loc );
            };
            unless ($ok) {
                if ( my $e = Exception::Class->caught('LacunaRPCException') ) {
                    print "done trash removal: $e\n";
                    exit;
                }
                else {
                    my $e = Exception::Class->caught();
                    ref $e ? $e->rethrow : die "$e\n";
                }
            }

            $last = 1
              if $waste_stored < $waste_cost;

            $junk->demolish( $ok->{building}->{id} )
              unless !$demolish && $last;

            last if $last;

            sleep 15;    # Server takes a few seconds to register demo
        }
    }
}

exit;

sub usage {
    die <<"END_USAGE";
Usage: $0 CONFIG_FILE
		--planet		 PLANET

CONFIG_FILE	 defaults to 'lacuna.yml'

--planet is the planet you want to remove trash from.
--x is the x-coordinate of the building location, defaults to 5
--y is the y-coordinate of the building location, defaults to -5

You must at least have access to the Junk Henge to use this script.

This scripts purges as much trash as possible from the planet, using the highest available junk building that is not currently built. 

END_USAGE

}

