#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            ();
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

my @incoming;

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    next unless $body->{incoming_foreign_ships};
    
    my $buildings = $result->{buildings};

    # Find the Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;
    
    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );
    
    my $ships = $space_port->view_foreign_ships->{ships};
    
    push @incoming, {
        name  => $name,
        ships => $ships,
    };
}

for my $planet (@incoming) {
    printf "%s\n", $planet->{name};
    print "=" x length $planet->{name};
    print "\n";
    
    for my $ship (@{ $planet->{ships} }) {
        
        my $type = $ship->{type_human} ? $ship->{type_human}
                 :                       'Unknown ship';
        
        my $from = $ship->{from}{name} ? sprintf( "%s [%s]",
                                            $ship->{from}{name},
                                            $ship->{from}{empire}{name} )
                 :                       'Unknown location';
        
        my $when = $ship->{date_arrives};
        
        print <<OUTPUT;
$type from $from
Arriving $when

OUTPUT
    }
}
