#!/usr/bin/perl
#
# Script to find all bodies known to you (via observatories)
# Will spit out a csv list of them for further data extractions
#
# Usage: perl probes.pl myaccount.yml
#  

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;
use Games::Lacuna::Client::Buildings::Observatory;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $probe_file = "probe_data.yml";
my $clean    = 0;
my $empire   = '';

GetOptions(
  'output=s' => \$probe_file,
  'clean' => \$clean,
  'empire=s' => \$empire,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$probe_file") || die "Could not open $probe_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 
  my $home_stat      = $client->body(id => $home_planet_id)->get_status();
  my $ename          = $home_stat->{body}->{empire}->{'name'};
  my ($hx,$hy)       = @{$home_stat->{body}}{'x','y'};

# Get obervatories;
  my @observatories;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    push @observatories, grep { $buildings->{$_}->{url} eq '/observatory' } keys %$buildings;
  }

  print "Observatory IDs: ".join(q{, },@observatories)."\n";

# Find stars
  my @stars;
  my @star_bit;
  for my $obs_id (@observatories) {
    my $pages = 1;
    do {
      @star_bit =
         @{$client->building( id => $obs_id, type => 'Observatory' )->get_probed_stars($pages++)->{stars}};
      if (@star_bit) {
        push @stars, @star_bit;
      }
    } until (@star_bit == 0)
  }

# Gather planet data
  my @bodies;
  for my $star (@stars) {
    my @tbod;
    if ($clean or $ename ne '') {
      for my $bod ( @{$star->{bodies}} ) {
        if ($empire ne '' and defined($bod->{empire})) {
          push @tbod, $bod if $bod->{empire}->{name} =~ /$empire/;
        }
        elsif (defined($bod->{empire}) && ($clean && ($bod->{empire}->{name} eq "$ename"))) {
          delete $bod->{building_count};
#          delete $bod->{empire};
          delete $bod->{energy_capacity};
          delete $bod->{energy_hour};
          delete $bod->{energy_stored};
          delete $bod->{food_capacity};
          delete $bod->{food_hour};
          delete $bod->{food_stored};
          delete $bod->{happiness};
          delete $bod->{happiness_hour};
          delete $bod->{needs_surface_refresh};
          delete $bod->{ore_capacity};
          delete $bod->{ore_hour};
          delete $bod->{ore_stored};
          delete $bod->{plots_available};
          delete $bod->{population};
          delete $bod->{waste_capacity};
          delete $bod->{waste_hour};
          delete $bod->{waste_stored};
          delete $bod->{water_capacity};
          delete $bod->{water_hour};
          delete $bod->{water_stored};
          push @tbod, $bod;
        }
      }
    }
    else {
      @tbod = @{$star->{bodies}};
    }
    push @bodies, @tbod if (@tbod);
  }

print OUTPUT $dumper->dump(\@bodies);
close(OUTPUT);

