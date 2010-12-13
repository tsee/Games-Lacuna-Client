#!/usr/bin/perl
#
# Just a proof of concept for Genetics lab

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $dump_file = "data_genetic.yml";
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

# Get Theme Park
  my @genetic;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ($planet_name eq "Vinland"); # Test Planet
    print "$planet_name\n";

    my @sybit = grep { $buildings->{$_}->{url} eq '/geneticslab' } keys %$buildings;
    if (@sybit) {
      print "Prepare the table!\n";
    }
    print OUTPUT $dumper->dump(\@sybit);
    push @genetic, @sybit;
  }

  print "Lab: ".join(q{, },@genetic)."\n";

  my @builds;
  my $em_bit;
  for my $sy_id (@genetic) {
    print "Stay awhile\n";
    $em_bit = $client->building( id => $sy_id, type => 'GeneticsLab' )->prepare_experiment();
#    $em_bit = $client->building( id => $sy_id, type => 'ThemePark' )->operate();
    push @builds, $em_bit;
  }

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

