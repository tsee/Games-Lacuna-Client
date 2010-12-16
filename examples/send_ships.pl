#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my @ship_names;
my @ship_types;
my $speed;
my $max;
my $from;
my $star;
my $planet;
my $dryrun;

GetOptions(
    'ship=s@'  => \@ship_names,
    'type=s@'  => \@ship_types,
    'speed=i'  => \$speed,
    'max=i'    => \$max,
    'from=s'   => \$from,
    'star=s'   => \$star,
    'planet=s' => \$planet,
    'dryrun!'  => \$dryrun,
);

usage() if !@ship_names && !@ship_types;

usage() if !$from;

usage() if !$star && !$planet;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};
my $target_id;
my $target_name;
my $target_type;

# Where are we sending to?

if ($star) {
    my $star_result = $client->map->get_star_by_name($star)->{star};
    
    if ($planet) {
        # send to planet on star
        my $bodies = $star_result->{bodies};
        
        my ($body) = first { $_->{name} eq $planet } @$bodies;
        
        die "Planet '$planet' not found at star '$star'"
            if !$body;
        
        $target_id   = $body->{id};
        $target_name = "$planet [$star]";
        $target_type = "body_id";
    }
    else {
        # send to star
        $target_id   = $star_result->{id};
        $target_name = $star;
        $target_type = "star_id";
    }
}
else {
    # send to own colony
    for my $key (keys %$planets) {
        if ( $planets->{$key} eq $planet ) {
            $target_id   = $key;
            $target_name = $planet;
            $target_type = "body_id";
            last;
        }
    }
    
    die "Colony '$planet' not found"
        if !$target_id;
}

# Where are we sending from?

my $from_id;

for my $key (keys %$planets) {
    if ( $planets->{$key} eq $from ) {
        $from_id = $key;
        last;
    }
}

die "From colony '$from' not found"
    if !$from_id;

# Load planet data
my $body      = $client->body( id => $from_id );
my $result    = $body->get_buildings;
my $buildings = $result->{buildings};

# Find the first Space Port
my $space_port_id = first {
        $buildings->{$_}->{name} eq 'Space Port'
} keys %$buildings;

my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

my $ships = $space_port->get_ships_for( $from_id, { body_id => $target_id}  );

my $available = $ships->{available};
my $sent = 0;

for my $ship ( @$available ) {
    next if @ship_names && !grep { $ship->{name} eq $_ } @ship_names;
    next if @ship_types && !grep { $ship->{type} eq $_ } @ship_types;
    next if $speed && $speed != $ship->{speed};
    
    if ($dryrun)
    {
      print qq{DRYRUN: };
    }
    else
    {
      $space_port->send_ship( $ship->{id}, { $target_type => $target_id } );
    }
    
    printf "Sent %s to %s\n", $ship->{name}, $target_name;
    
    $sent++;
    last if $max && $max == $sent;
}


sub usage {
  die <<"END_USAGE";
Usage: $0 send_ship.yml
       --ship       NAME
       --type       TYPE
       --speed      SPEED
       --max        MAX
       --from       NAME  (required)
       --star       NAME
       --planet     NAME
       --dryrun

Either of --ship_name or --type is required.

--ship_name can be passed multiple times.

--type can be passed multiple times.
It must match the ship's "type", not "type_human", e.g. "scanner", "spy_pod".

If --max is set, this is the maximum number of matching ships that will be
sent. Default behaviour is to send all matching ships.

--from is the colony from which the ship should be sent.

If --star is missing, the planet is assumed to be one of your own colonies.

At least one of --star or --planet is required.

If --dryrun is specified, nothing will be sent, but all actions that WOULD
happen are reported

END_USAGE

}
