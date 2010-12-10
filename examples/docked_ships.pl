#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
);

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

my $available = 'Docks Available';

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if defined $planet_name && $planet_name ne $name;

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the first Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;
    
    next if !$space_port_id;
    
    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' )->view;
    
    my $ships = $space_port->{docked_ships};
    
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    my $max_length = max( map { length _prettify_name($_) } keys %$ships )
                   || 0;
    
    $max_length = length($available) > $max_length ? length $available
                :                                    $max_length;
    
    for my $type ( sort keys %$ships ) {
        printf "%${max_length}s: %d\n",
            _prettify_name( $type ),
            $ships->{$type};
    }
    
    printf "%${max_length}s: %d\n",
        $available,
        $space_port->{docks_available};
    
    print "\n";
}

sub _prettify_name {
    my $name = shift;
    
    $name = ucfirst $name;
    $name =~ s/_(\w)/" ".ucfirst($1)/ge;
    
    return $name;
}
