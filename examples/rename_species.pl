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
my $name;
my $desc;
my $help;

GetOptions(
    'planet=s'   => \$planet,
    'name=s'     => \$name,
    'description=s' => \$desc,
	'help|h'     => \$help,
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

# Find the GeneticsLab
my $genlab_id = first {
        $buildings->{$_}->{url} eq '/geneticslab'
} keys %$buildings;

die "No Genetics Lab on this planet\n"
	if !$genlab_id;

my $genlab = $client->building( id => $genlab_id, type => 'GeneticsLab' );

my $ret = $genlab->rename_species( { name => $name, description => $desc } );

print Dumper( $ret );


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet    PLANET_NAME
    --name      New species name
    --desc      New species description

CONFIG_FILE  defaults to 'lacuna.yml'

END_USAGE

}
