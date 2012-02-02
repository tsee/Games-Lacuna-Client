#!/usr/bin/perl

use strict;
use warnings;
use DateTime;
use Getopt::Long qw( GetOptions );
use List::Util   qw( first );
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my %opts;

GetOptions(
    \%opts,
    'planet=s',
    'orbiting=s',
    'type=s',
    'max=i',
    'rename',
    'all',
    'dryrun|dry-run',
);

usage() if !exists $opts{planet};

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
	cfg_file  => $cfg_file,
    rpc_sleep => 1,
	 #debug    => 1,
);

my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Load planet data
my $body = $client->body( id => $planets{ $opts{planet} } );

my $buildings = $body->get_buildings->{buildings};

# Find the first Space Port
my $space_port_id = first {
        $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;

my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

my $ships = $opts{all} ? recall_all()
          :              recall_select();

exit if $opts{dryrun};

exit if !$opts{rename};

rename_ships( $ships );

exit;


sub recall_all {
    if ( $opts{dryrun} ) {
        warn "Would have called recall_all()\n";
        return [];
    }

    return $space_port->recall_all->{ships};
}

sub recall_select {
    # get all defending ships
    my $ships = $space_port->get_ships_for(
            $planets{ $opts{planet} },
            {
                body_name => $opts{orbiting},
            },
        )->{orbiting};

    if ( exists $opts{type} ) {
        @$ships =
            grep {
                $_->{type} eq $opts{type}
            } @$ships;
    }

    die "Matched no ships\n"
        if !@$ships;

    if ( $opts{max} && @$ships > $opts{max} ) {
        $#$ships = $opts{max}-1;
    }

    if ( $opts{dryrun} ) {
        print "DRYRUN\n";
        print "======\n";
    }

    # recall
    for my $ship (@$ships) {
        $space_port->recall_ship( $ship->{id} )
            unless $opts{dryrun};

        printf "%s recalled\n",
            $ship->{name};
    }

    return $ships;
}

# rename ships
sub rename_ships {
    my ( $ships ) = @_;

    print "\n";

    for my $ship (@$ships) {

        my $name = $ship->{type_human};

        $space_port->name_ship(
            $ship->{id},
            $name,
            );

        printf qq{Renamed "%s" to "%s"\n},
            $ship->{name},
            $name;
    }
}

exit;

sub usage {
  die <<"END_USAGE";
Usage: $0 lacuna.yml
       --planet   NAME  # Required. Name of planet which controls the ship
       --orbiting NAME  # Name of body the ship is orbiting
       --type     TYPE  # Type of ship
       --max      MAX   # Max number of ships to recall
       --all
       --rename
       --dryrun

--type
By default, all ships defending the specified body are recalled.
Ships which may currently be used for defense are 'fighter' and 'spy_shuttle'.

If --rename is provided, each ship sent will be renamed using the ship-type.

If --dryrun is provided, just report which ships would be recalled.

If --all is provided, then --orbiting, --type and --max are ignored.
The "recall_all" API method will be used to recall all this planet's remotely
defending and orbiting ships with a single API call.

END_USAGE

}
