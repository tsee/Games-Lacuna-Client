#!/usr/bin/perl

use strict;
use warnings;
use List::Util     qw(max sum);
use Getopt::Long   qw(GetOptions);
use Number::Format qw(format_number);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

my $planet;
my $sort;
my $reverse;
my @types = qw( food ore water energy waste happiness );

GetOptions(
    'planet=s' => \$planet,
    'sort=s'   => \$sort,
    'reverse'  => \$reverse,
);

usage() if !$planet;
usage() if $sort && !grep { $_ eq lc $sort } @types;

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
	# debug    => 1,
);

# Load the planets
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Load planet data
my $body   = $client->body( id => $planets{$planet} );
my $result = $body->get_buildings;

my $buildings = $result->{buildings};

my @detail;

for my $id ( keys %$buildings ) {
    my $type     = Games::Lacuna::Client::Buildings::type_from_url( $buildings->{$id}{url} );
    my $building = $client->building( id => $id, type => $type );
    
    push @detail, $building->view->{building};
}

if ( $sort ) {
    $sort = lc $sort;
    
    @detail = sort {
        $a->{"${sort}_hour"} <=> $b->{"${sort}_hour"}
    } @detail;
}
else {
    # sort by total production
    
    # don't include waste or happiness
    my @types = qw( food ore water energy );
    
    @detail = sort {
        my $a_total = sum( @{$a}{ map { "${_}_hour" } @types } );
        my $b_total = sum( @{$b}{ map { "${_}_hour" } @types } );
        $a_total <=> $b_total;
    } @detail;
}

if ( $reverse ) {
    @detail = reverse @detail;
}

print "Planet: $planet\n\n";

for my $building (@detail) {
    printf "%s, level %d (%d, %d)\n",
        $building->{name},
        $building->{level},
        $building->{x},
        $building->{y};
    
    my $max = max map { length format_number $building->{"${_}_hour"} } @types;
    
    for my $type (@types) {
        printf "%6s/hr: %${max}s\n",
            ucfirst($type),
            format_number( $building->{"${type}_hour"} );
    }
    
    print "\n";
}


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet PLANET_NAME
    --sort   SORT
    --reverse
    --help

CONFIG_FILE  defaults to 'lacuna.yml'

SORT must be one of 'food', 'ore', 'water', 'energy', 'waste'

Warning: makes an API call for every building on the planet.

END_USAGE

}
