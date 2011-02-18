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
my $leave = 0;
my $from;
my $x;
my $y;
my $star;
my $own_star;
my $planet;
my $dryrun;

GetOptions(
    'ship=s@'  => \@ship_names,
    'type=s@'  => \@ship_types,
    'speed=i'  => \$speed,
    'max=i'    => \$max,
    'leave=i'  => \$leave,
    'from=s'   => \$from,
    'x=i'      => \$x,
    'y=i'      => \$y,
    'star=s'   => \$star,
    'planet=s' => \$planet,
    'own-star' => \$own_star,
    'dryrun!'  => \$dryrun,
);

usage() if !@ship_names && !@ship_types;

usage() if !$from;

usage() if !$star && !$planet && !$own_star && !defined $x && !defined $y;

usage() if defined $x && !defined $y;
usage() if defined $y && !defined $x;

usage() if $own_star && $planet;

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
	 #debug    => 1,
);

my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

die "--from colony '$from' not found"
    if !$planets{$from};

my $target;
my $target_name;

# Where are we sending to?

if ( defined $x && defined $y ) {
    $target      = { x => $x, y => $y };
    $target_name = "$x,$y";
}
if ($star) {
    my $star_result = $client->map->get_star_by_name($star)->{star};
    
    if ($planet) {
        # send to planet on star
        my $bodies = $star_result->{bodies};
        
        my ($body) = first { $_->{name} eq $planet } @$bodies;
        
        die "Planet '$planet' not found at star '$star'"
            if !$body;
        
        $target      = { body_id => $body->{id} };
        $target_name = "$planet [$star]";
    }
    else {
        # send to star
        $target      = { star_id => $star_result->{id} };
        $target_name = $star;
    }
}
elsif ($own_star) {
    my $body = $client->body( id => $planets{$from} )->get_status;
    
    $target      = { star_id => $body->{body}{star_id} };
    $target_name = "own star";
}
else {
    # send to own colony
    my $target_id = $planets{$planet}
        or die "Colony '$planet' not found\n";
    
    $target      = { body_id => $target_id };
    $target_name = $planet;
}

# Load planet data
my $body      = $client->body( id => $planets{$from} );
my $result    = $body->get_buildings;
my $buildings = $result->{buildings};

# Find the first Space Port
my $space_port_id = first {
        $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;

my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

my $ships = $space_port->get_ships_for(
    $planets{$from},
    $target,
);

my $available = $ships->{available};
my $sent = 0;
my $kept = 0;

for my $ship ( @$available ) {
    next if @ship_names && !grep { $ship->{name} eq $_ } @ship_names;
    next if @ship_types && !grep { $ship->{type} eq $_ } @ship_types;
    
    if ( $leave > $kept ) {
        $kept++;
        next;
    }
    
    next if $speed && $speed != $ship->{speed};
    
    if ($dryrun)
    {
        print qq{DRYRUN: };
    }
    else
    {
        $space_port->send_ship( $ship->{id}, $target );
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
       --leave      COUNT
       --from       NAME  (required)
       --x          COORDINATE
       --y          COORDINATE
       --star       NAME
       --planet     NAME
       --own_star
       --dryrun

Either of --ship_name or --type is required.

--ship_name can be passed multiple times.

--type can be passed multiple times.
It must match the ship's "type", not "type_human", e.g. "scanner", "spy_pod".

If --max is set, this is the maximum number of matching ships that will be
sent. Default behaviour is to send all matching ships.

If --leave is set, this number of ships will be kept on the planet. This counts
all ships of the desired type, regardless of any --speed setting.

--from is the colony from which the ship should be sent.

If --star is missing, the planet is assumed to be one of your own colonies.

At least one of --star or --planet or --own_star or both --x and --y are
required.

--own_star and --planet cannot be used together.

If --dryrun is specified, nothing will be sent, but all actions that WOULD
happen are reported

END_USAGE

}
