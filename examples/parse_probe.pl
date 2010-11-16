#!/usr/bin/perl
#
# Script to parse thru the probe data
#
# Usage: perl parse_probe.pl probe_file
#  
use strict;
use warnings;
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use Data::Dumper;

my $home_x = 0;
my $home_y = 0;
my $probe_file = "probe_data.yml";

GetOptions(
  'x=i' => \$home_x,
  'y=i' => \$home_y,
  'p=s' => \$probe_file,
);
  
  my $bod;
  my $bodies = YAML::LoadFile($probe_file);

#  print Dumper($bodies);
#exit;

# Calculate some metadata
  for $bod (@$bodies) {
    $bod->{distance} = sqrt(($home_x - $bod->{x})**2 + ($home_y - $bod->{y})**2);
  }


for $bod (@$bodies) {
  if (not defined($bod->{empire}->{name})) { $bod->{empire}->{name} = "unclaimed"; } 
  if (not defined($bod->{water})) { $bod->{water} = 0; } 
  $bod->{image} =~ s/-.//;
  print join(",", $bod->{star_name}, $bod->{star_id}, $bod->{distance}, $bod->{orbit}, $bod->{image},
                         $bod->{name}, $bod->{x}, $bod->{y}, $bod->{empire}->{name},
                         $bod->{size}, $bod->{type}, $bod->{water});
  for my $ore (sort keys %{$bod->{ore}}) {
    print ",$ore,",$bod->{ore}->{$ore};
  }
  print "\n";
}

