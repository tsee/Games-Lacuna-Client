#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Number::Format        qw( format_number );
use List::Util            qw( max );
use Getopt::Long          qw(GetOptions);
use Games::Lacuna::Client ();

my $planet_name;
my $use_seconds_left = 0;

GetOptions(
    'planet=s' => \$planet_name,
    'seconds!' => \$use_seconds_left,
);
require Time::Duration if $use_seconds_left;

my $cfg_file = Games::Lacuna::Client->get_config_file([shift(@ARGV) || 'lacuna.yml']);

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = {reverse(%{$empire->{planets}})};

# Scan each planet
foreach my $name ( sort keys %$planets ) {
    my $planet_id = $planets->{$name};

    next if defined $planet_name && $planet_name ne $name;

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

    for my $building (sort { $a->{pending_build}{seconds_remaining} <=> $b->{pending_build}{seconds_remaining} } @build) {
        printf "%s: %s\n",
            $building->{name},
            $use_seconds_left ? Time::Duration::duration($building->{pending_build}{seconds_remaining}) : $building->{pending_build}{end};
    }

    print "\n";
}
