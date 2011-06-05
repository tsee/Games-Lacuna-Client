#!/usr/bin/perl
# Simple script for renaming species and description
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
    'desc=s'     => \$desc,
    'help|h'     => \$help,
);

usage() if $help;
usage() if !$planet;
usage() if !$name;
usage() if !$desc;

if ((length($name) > 30) or length($desc) > 1024) {
  print "Length Exceeded! Name was ",length($name),
        " and description was ",length($desc),"\n";
  usage();
}
if ($name =~ /[@&<>;]/ or $desc =~ /[<>]/) {
  print "Bad Characters in name or description\n";
  usage();
}

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
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

my $hash = {
   name => $name,
   description => $desc,
};

my $return = $genlab->rename_species($hash);


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --planet PLANET_NAME (Needs Genetic Lab)
       --name   NEW SPECIES NAME (Max 30 chars, No @&<>;)
       --desc   DESCRIPTION (Max 1024 chars, No <>)
       --help

CONFIG_FILE  defaults to 'lacuna.yml'

END_USAGE

}
