#!/usr/bin/perl

use strict;
use warnings;
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

@ARGV = ('../lacuna.yml');

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my @ship_names = ('Scanner 10');
my $from = 'Conflag';
my $star;
my $planet = 'Ember';

GetOptions(
    'ship=s@'  => \@ship_names,
    'from=s'   => \$from,
    'star=s'   => \$star,
    'planet=s' => \$planet,
);

usage() if !@ship_names || !$from;

usage() if !$star && !$planet;

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

my %sent;

for my $ship_name (@ship_names) {
    for my $ship ( @$available ) {
        next if $ship->{name} ne $ship_name;
        next if $sent{ $ship->{id} };
        
        $space_port->send_ship( $ship->{id}, { $target_type => $target_id } );
        
        printf "Sent %s to %s\n", $ship->{name}, $target_name;
        
        $sent{ $ship->{id} } = 1;
        last;
    }
}


sub usage {
  die <<"END_USAGE";
Usage: $0 send_ship.yml
       --ship       NAME  (required)
       --from       NAME  (required)
       --star       NAME
       --planet     NAME

--ship_name can be passed multiple times.

--from is the colony from which the ship should be sent.

If --star is missing, the planet is assumed to be one of your own colonies.

At least one of --star or --planet is required.

END_USAGE

}
