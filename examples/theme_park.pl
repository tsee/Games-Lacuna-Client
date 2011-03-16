#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use List::Util   qw( first );
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my $planet;
my $operate;
my $count = 1;
my $help;

GetOptions(
    'planet=s' => \$planet,
    'operate'  => \$operate,
    'count=i'  => \$count,
    'help|h'   => \$help,
);

usage() if $help;
usage() if !$planet;

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

# Find the ThemePark
my $themepark_id = first {
        $buildings->{$_}->{url} eq '/themepark'
} keys %$buildings;

die "No Theme Park on this planet\n"
	if !$themepark_id;

my $themepark = $client->building( id => $themepark_id, type => 'ThemePark' );

if ( $operate ) {
    for ( 1 .. $count ) {
        my $return = $themepark->operate->{themepark};
        
        print "Success\n";
        
        if ( $return->{can_operate} ) {
            my $food_count = $return->{food_type_count};
            
            print "Can operate the Theme Park again\n";
            printf "We have the %d foods required\n", $food_count;
        }
        else {
            print "Cannot operate again:\n";
            printf "%s\n", $return->{reason}[1];
        }
    }
}
else {
    my $return = $themepark->view->{themepark};
    
    if ( $return->{can_operate} ) {
        my $food_count = $return->{food_type_count} || 0;
        
        print "Can operate the Theme Park\n";
        printf "We have the %d foods required\n", $food_count;
    }
    else {
        print "Cannot operate the Theme Park:\n";
        printf "%s\n", $return->{reason}[1];
    }
}

exit;


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet PLANET_NAME
    --count  COUNT
    --operate
    --help

CONFIG_FILE  defaults to 'lacuna.yml'

COUNT is the number of times to operate the Theme Park. Defaults to 1.

END_USAGE

}
