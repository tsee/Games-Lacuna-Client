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

my $embassy_file = "data_embassy.yml";
GetOptions(
  'o=s' => \$embassy_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$embassy_file") || die "Could not open $embassy_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Embassies
  my @embassy;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};

    my @sybit = grep { $buildings->{$_}->{name} eq 'Embassy' } keys %$buildings;
    
    push @embassy, @sybit;
  }

  print "Embassy IDs: ".join(q{, },@embassy)."\n";

# Find embassy
  my @builds;
  my $em_bit;
  my %donate_hash;
  $donate_hash{"water"} = 500;
#  my $donate =  {
#      'water' => 5000,
#      'monazite' => 30000,
#      'shake' => 1000,
#    };
  for my $sy_id (@embassy) {
    $em_bit = $client->building( id => $sy_id, type => 'Embassy' )->donate_to_stash(\%donate_hash);
    $em_bit = $client->building( id => $sy_id, type => 'Embassy' )->view_stash();
    push @builds, $em_bit;
  }

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

