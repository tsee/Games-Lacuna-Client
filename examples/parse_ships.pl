#!/usr/bin/perl
#
# Script to parse thru the ship data
#
# Usage: perl parse_ships.pl probe_file
#  
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use YAML;
use Data::Dumper;

my $ship_file = "ship_data.yml";

GetOptions(
  'p=s' => \$ship_file,
);
  
  my $ship_yards = YAML::LoadFile($ship_file);

# Print out data
  my $yard;
  print "Type,Speed,Hold,Stealth,Food,Ore,Water,Energy,Waste,Time,Planet,Cloak,Crash,Prop,Pilot,Shipyard,TM\n";
  for $yard (@$ship_yards) {
    for my $ship (keys %{$yard->{buildable}}) {
      print join(",",
        $yard->{buildable}->{"$ship"}->{type_human},
        $yard->{buildable}->{"$ship"}->{attributes}->{speed},
        $yard->{buildable}->{"$ship"}->{attributes}->{hold_size},
        $yard->{buildable}->{"$ship"}->{attributes}->{stealth},
        $yard->{buildable}->{"$ship"}->{cost}->{food},
        $yard->{buildable}->{"$ship"}->{cost}->{ore},
        $yard->{buildable}->{"$ship"}->{cost}->{water},
        $yard->{buildable}->{"$ship"}->{cost}->{energy},
        $yard->{buildable}->{"$ship"}->{cost}->{waste},
        $yard->{buildable}->{"$ship"}->{cost}->{seconds},
        $yard->{planet}->{pname},
        $yard->{planet}->{'Cloaking Lab'},
        $yard->{planet}->{'Crashed Ship Site'},
        $yard->{planet}->{'Propulsion System Factory'},
        $yard->{planet}->{'Pilot Training Facility'},
        $yard->{planet}->{'Shipyard'},
        $yard->{planet}->{'Trade Ministry'}),"\n";
    }
  }

exit;
