#!/usr/bin/perl

use strict;
use warnings;
use Number::Format        qw( format_number );
use List::Util            qw( max );
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my @types = qw( food ore water energy waste );

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};
    
    my @build;
    
    for my $building_id ( sort keys %$buildings ) {
        push @build, $buildings->{$building_id}
            if $buildings->{$building_id}{pending_build};
    }
    
    next if !@build;
    
    print "$name\n";
    print "=" x length $name;
    print "\n";
    
    for my $building (@build) {
        printf "%s: %s\n",
            $building->{name},
            $building->{pending_build}{end};
    }
    
    print "\n";
}
