#!/usr/bin/perl
#

use strict;
use warnings;
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $ship_file = "ship_data.yml";
GetOptions(
  'o=s' => \$ship_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$ship_file") || die "Could not open $ship_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Shipyards
  my @shipyards;
  my %shipy_hash;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};

    my @sybit = grep { $buildings->{$_}->{name} eq 'Shipyard' } keys %$buildings;
    
    push @shipyards, @sybit;
    for my $sid (@sybit) {
      $shipy_hash{$sid}->{'Cloaking Lab'} = 0;
      $shipy_hash{$sid}->{'Crashed Ship Site'} = 0;
      $shipy_hash{$sid}->{'Pilot Training Facility'} = 0;
      $shipy_hash{$sid}->{'Propulsion System Factory'} = 0;
      $shipy_hash{$sid}->{'Trade Ministry'} = 0;
      $shipy_hash{$sid}->{Shipyard} = $buildings->{$sid}->{level};
      $shipy_hash{$sid}->{pname} = $planet_name;
    }
    for my $bld (keys %$buildings) {
      if ( ( $buildings->{$bld}->{name} eq 'Propulsion System Factory' ) ||
           ( $buildings->{$bld}->{name} eq 'Cloaking Lab' ) ||
           ( $buildings->{$bld}->{name} eq 'Trade Ministry' ) ||
           ( $buildings->{$bld}->{name} eq 'Crashed Ship Site' ) ||
           ( $buildings->{$bld}->{name} eq 'Pilot Training Facility' ) ) {
        for my $sid (@sybit) {
          $shipy_hash{$sid}->{$buildings->{$bld}->{name}} =
            $buildings->{$bld}->{level};
        }
      }
    }
  }

  print "Shipyard IDs: ".join(q{, },@shipyards)."\n";

# Find shipyard builds
  my @builds;
  my $ship_bit;
  for my $sy_id (@shipyards) {
    $ship_bit = $client->building( id => $sy_id, type => 'Shipyard' )->get_buildable();
    my $id_hash;
    $id_hash->{buildable} = $ship_bit->{buildable};
    $id_hash->{planet} = $shipy_hash{$sy_id};
    push @builds, $id_hash;
  }

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

