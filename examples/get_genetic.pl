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
use Exception::Class;

  my $test_planet = "Test Planet"; #ZZZ Change this to your genetic lab planet
  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $dump_file = "data/data_genetic.yml";
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
  my $my_aff         = $data->{species};
  delete $data->{species}->{description}; # Non-number, not important
  delete $data->{species}->{name};      # Non-number, not important
  delete $data->{species}->{min_orbit}; # Can not change this

# Get Genetic Lab
  my @genetic;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ($planet_name eq "$test_planet"); # We only do one planet, set it above
    print "$planet_name\n";

    my @sybit = grep { $buildings->{$_}->{url} eq '/geneticslab' } keys %$buildings;
    if (@sybit) {
      print "Prepare the table!\n";
    }
    print OUTPUT $dumper->dump(\@sybit);
    push @genetic, @sybit;
  }

  print "Lab: ".join(q{, },@genetic)."\n";

  my $em_bit;
  my $spy_id = 0; # Run first as this, then put in the spy ID you want with appropriate aff uncommented below
#  my $aff_id =  "deception_affinity";
  my $aff_id =  "environmental_affinity";
#  my $aff_id =  "mining_affinity";
#  my $aff_id =  "max_orbit";
#  my $aff_id =  "research_affinity";
#  my $aff_id =  "farming_affinity";
#  my $aff_id =  "management_affinity";
#  my $aff_id =  "science_affinity";
#  my $aff_id =  "political_affinity";
#  my $aff_id =  "trade_affinity";
#  my $aff_id =  "growth_affinity";
  my $sy_id = $genetic[0];
  my $ok = eval {
    if ($spy_id == 0) {
      print "Checking stats in lab $sy_id\n";
      $em_bit = $client->building( id => $sy_id, type => 'GeneticsLab' )->prepare_experiment();
    }
    else {
      print "Under the knife in lab $sy_id trying for $aff_id\n";
      $em_bit = $client->building( id => $sy_id, type => 'GeneticsLab' )->run_experiment($spy_id, $aff_id);
    }
    return 1;
  };
  unless ($ok) {
    if (my $e =  Exception::Class->caught('LacunaRPCException')) {
      print "Code: ", $e->code, "\n";
    }
    else {
      print "Non-OK result\n";
    }
  }

print OUTPUT $dumper->dump($em_bit);
close(OUTPUT);

  if ($ok) {
    if ($spy_id == 0) {
      for my $taff (sort keys %$my_aff) {
         printf "%22s : %s\n", $taff,$my_aff->{$taff};
      }
      print "Survival Odds: ", $em_bit->{"survival_odds"},"\n";
      print "Graft Odds: ", $em_bit->{"graft_odds"},"\n";
      for my $spy ( @{$em_bit->{"grafts"}}) {
        print "Spy ", $spy->{"spy"}->{"name"}, ": ", $spy->{"spy"}->{"id"},"\n";
        for my $taff (sort keys %$my_aff) {
          if ( defined($spy->{"species"}->{$taff}) && $spy->{"species"}->{$taff} > $my_aff->{$taff} ) {
            print "  $taff: ", $my_aff->{$taff}, "->", $spy->{"species"}->{$taff}, "\n";
          }
        }
      }
    }
    else {
      if ($em_bit->{"experiment"}->{"graft"}) {
        print "Success with $aff_id! ",$em_bit->{"experiment"}->{"message"},"\n";
      }
      else {
        print "Failure with $aff_id! ",$em_bit->{"experiment"}->{"message"},"\n";
      }
    }
  }

