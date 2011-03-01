#!/usr/bin/perl
#
# Script to parse thru the probe data
#
# Usage: perl parse_probe.pl probe_file
#  
# Write this to put out system stats
#
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::XS;
use Data::Dumper;
use utf8;

my $home_x = 0;
my $home_y = 0;
my $probe_file = "data/probe_data_cmb.yml";

GetOptions(
  'x=i' => \$home_x,
  'y=i' => \$home_y,
  'p=s' => \$probe_file,
);

  my $bod;
  my $bodies = YAML::XS::LoadFile($probe_file);
  my $stars  = get_stars("data/stars.csv");

#  print YAML::XS::Dump($stars); exit;
# Calculate some metadata
  for $bod (@$bodies) {
    $bod->{distance} = sqrt(($home_x - $bod->{x})**2 + ($home_y - $bod->{y})**2);
    $bod->{sdistance} = sqrt(($home_x - $stars->{$bod->{star_id}}->{x})**2 + ($home_y - $stars->{$bod->{star_id}}->{y})**2);
  }


for $bod (@$bodies) {
  if (not defined($bod->{empire}->{name})) { $bod->{empire}->{name} = "unclaimed"; } 
  if (not defined($bod->{water})) { $bod->{water} = 0; } 
  $bod->{image} =~ s/-.//;
  print join(",", $bod->{star_name}, $bod->{star_id}, $bod->{sdistance}, $stars->{$bod->{star_id}}->{x},
                  $stars->{$bod->{star_id}}->{y},  $bod->{distance}, $bod->{orbit}, $bod->{image},
                         $bod->{name}, $bod->{x}, $bod->{y}, $bod->{empire}->{name},
                         $bod->{size}, $bod->{type}, $bod->{water});
#  for my $ore (sort keys %{$bod->{ore}}) {
#    print ",$ore,",$bod->{ore}->{$ore};
#  }
  print "\n";
}

sub get_stars {
  my ($sfile) = @_;

  my $fh;
  open ($fh, "<", "$sfile") or die;

  my $fline = <$fh>;
  my %star_hash;
  while(<$fh>) {
    chomp;
    my ($id, $name, $x, $y, $color, $zone) = split(/,/, $_, 6);
    $star_hash{$id} = {
      id    => $id,
      name  => $name,
      x     => $x,
      y     => $y,
      color => $color,
      zone  => $zone,
    }
  }
  print
  return \%star_hash;
}
