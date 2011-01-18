#!/usr/bin/perl
#
# Just a proof of concept to make sure dump works for each storage

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

  $dump_planet = "Test Planet here";


  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $dump_file = "data/data_dump.yml";
GetOptions(
  'o=s' => \$dump_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$dump_file") || die "Could not open $dump_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Storage
  my @dump;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ($planet_name eq "$test_planet"); # Test Planet
    print "$planet_name\n";

    my @sybit = grep { $buildings->{$_}->{url} eq '/orestorage' } keys %$buildings;
#    my @sybit = grep { $buildings->{$_}->{url} eq '/foodreserve' } keys %$buildings;
#    my @sybit = grep { $buildings->{$_}->{url} eq '/energyreserve' } keys %$buildings;
#    my @sybit = grep { $buildings->{$_}->{url} eq '/waterstorage' } keys %$buildings;
    if (@sybit) {
      print "Storage!\n";
    }
#    print OUTPUT $dumper->dump(\@sybit);
    push @dump, @sybit;
  }

  print "Storage: ".join(q{, },@dump)."\n";

# Find dump
  my @builds;
  my $em_bit;
  my $sy_id = pop(@dump);
  print "Trying to Dump\n";
#    $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->view();
#  $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("beryl", "600000");
  $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("fluorite", "1000000");
  $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("monazite", "5000000");
#  $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("chalcopyrite", "1000000");
#    $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("gypsum", "150000");
#    $em_bit = $client->building( id => $sy_id, type => 'OreStorage' )->dump("methane", "280000");
#    $em_bit = $client->building( id => $sy_id, type => 'FoodReserve' )->dump("wheat", "2000");
#    $em_bit = $client->building( id => $sy_id, type => 'EnergyReserve' )->dump("2000");
#    $em_bit = $client->building( id => $sy_id, type => 'WaterStorage' )->dump("2000");
    push @builds, $em_bit;

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

