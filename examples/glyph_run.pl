#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long          qw(GetOptions);
use List::Util            qw( first );
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

use Data::Dumper;

my $planet_name;
my @glyphs;
my $use_delay = 0;

GetOptions(
    'planet=s' => \$planet_name,
    'glyph=s'  => \@glyphs,
    'use_delay' => \$use_delay,
);

usage() if !@glyphs;

my $cfg_file = Games::Lacuna::Client->get_config_file([shift(@ARGV), 'lacuna.yml']);
sleep((localtime)[2]) if ($use_delay);

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_} => $_ } keys %{ $empire->{planets} };
my @selected_planets = keys %planets;
if ($planet_name)
{
    @selected_planets = grep { $_ eq $planet_name } keys %planets;
}

my %requestedGlyphs = map { $_ => 1 } @glyphs;

foreach $planet_name (@selected_planets)
{
    my $body      = $client->body( id => $planets{$planet_name} );
    my $buildings = $body->get_buildings->{buildings};
    my $arch_id = first {
            $buildings->{$_}->{url} eq '/archaeology'
    } keys %$buildings;
    next unless $arch_id;

    my $building = $client->building( id => $arch_id, type => '/archaeology' );
    next unless $building;

    if ($buildings->{$arch_id}->{work})
    {
        print "Skipping '$planet_name' as it is busy working\n";
        next;
    }

    my $buildingOre = $building->get_ores_available_for_processing();

    my $searching = 0;
    foreach my $ore (@glyphs)
    {
        next unless $buildingOre->{ore}->{$ore};
        my $return;
        eval {
            $return = $building->search_for_glyph($ore);
            $searching = 1;
        };
        
        if ($@) {
            warn "'$planet_name' - Error: $@\n";
            next;
        }

        print "'$planet_name' searching for $ore\n";
        last;
    }
    if (!$searching)
    {
        print "Can't find any of ", (join ',', keys %requestedGlyphs), " on planet '$planet_name'\n";
        next;
    }
    
}

exit;

sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet     PLANET
    --glyph      GLYPH

CONFIG_FILE  defaults to 'lacuna.yml'

--planet is the planet that your archmin is on.

--glyph is the glyph you want to search for.
    Multiple options can be provided with multiple --glyphs. It will search for the first available one

END_USAGE

}
