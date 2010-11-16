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

my $plat_file = "platform.yml";

GetOptions(
  'p=s' => \$plat_file,
);
  
  my $platforms = YAML::LoadFile($plat_file);

#  print Dumper($platforms);
#exit;

# Calculate some metadata
  my $plat;
  for $plat (@$platforms) {
  }


  for $plat (sort byplatsort @$platforms) {
    $plat->{distance} = sqrt(($plat->{hx} - $plat->{asteroid}->{x})**2 +
                             ($plat->{hy} - $plat->{asteroid}->{y})**2);
    $plat->{asteroid}->{image} =~ s/-.//;
    my $ore_atot = 0;
    my $ore_etot = 0;
    my @ore_a; my @ore_e;
    for my $ore_s (sort keys %{$plat->{asteroid}->{ore}}) {
      if ($plat->{asteroid}->{ore}->{$ore_s} > 1) {
        $ore_atot += $plat->{asteroid}->{ore}->{$ore_s};
      }
      push @ore_a, $plat->{asteroid}->{ore}->{$ore_s};
    }
    for my $ore_s (grep { /_hour$/ } keys %$plat) {
      if ($plat->{$ore_s} > 1) {
        $ore_etot += $plat->{$ore_s};
      }
      push @ore_e, $plat->{$ore_s};
    }
    print join(",",
      $plat->{planet},
      $plat->{shipping_capacity},
      $plat->{asteroid}->{name},
      $plat->{asteroid}->{x},
      $plat->{asteroid}->{y},
      $plat->{distance},
      $plat->{asteroid}->{size},
      $plat->{asteroid}->{orbit},
      $plat->{asteroid}->{image},
      $plat->{max_platforms},
      $ore_etot, $ore_atot, @ore_e, @ore_a
      );
    print "\n";
  }
exit;

sub byplatsort {
    $a->{planet} cmp $b->{planet} ||
    $a->{asteroid}->{star_name} cmp $b->{asteroid}->{star_name} ||
    $a->{asteroid}->{orbit} <=> $b->{asteroid}->{orbit};
#    $a->{distance} <=> $b->{distance};
}

