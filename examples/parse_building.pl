#!/usr/bin/env perl
#
# Script to parse thru the probe data
#
# Usage: perl parse_probe.pl probe_file
#  
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON;
use Data::Dumper;
use utf8;
binmode STDOUT, ":utf8";

my $bld_file = "data/data_builds.js";
my $help = 0;

GetOptions(
  'help' => \$help,
  'input=s' => \$bld_file,
);
  if ($help) {
    print "parse_building.pl --input input\n";
    exit;
  }
  
  my $json = JSON->new->utf8(1);
  open(BLDS, "$bld_file") or die "Could not open $bld_file\n";
  my $lines = join("",<BLDS>);
  my $bld_data = $json->decode($lines);
  close(BLDS);
#  print $json->pretty->encode($bld_data->{Oslo});


  print "Planet,Name,lvl,x,y,lvl2b,bldid,upgrade,working\n";
  for my $planet (sort keys %$bld_data) {
    next if $planet eq "planets";
    for my $bldid (keys %{$bld_data->{"$planet"}}) {
      my $working = defined($bld_data->{"$planet"}->{"$bldid"}->{work}) ?
                      $bld_data->{"$planet"}->{"$bldid"}->{work}->{seconds_remaining} : "";
      my $upgrade = defined($bld_data->{"$planet"}->{"$bldid"}->{pending_build}) ?
                      $bld_data->{"$planet"}->{"$bldid"}->{pending_build}->{seconds_remaining} : "";
      print join(",",
          $planet,
          $bld_data->{"$planet"}->{"$bldid"}->{name},
          $bld_data->{"$planet"}->{"$bldid"}->{level},
          $bld_data->{"$planet"}->{"$bldid"}->{x},
          $bld_data->{"$planet"}->{"$bldid"}->{y},
          $bld_data->{"$planet"}->{"$bldid"}->{leveled},
          $bldid, $upgrade, $working
          );
      print "\n";
    }
  }
exit;
