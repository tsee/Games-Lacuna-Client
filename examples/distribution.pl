#!/usr/bin/perl
#
# Just a proof of concept for distribution center

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;


  my $dump_file = "data/data_distribution.yml";
  my $planet_name;
  my $cfg_file = "lacuna.yml";
  my $help;

  GetOptions(
    'output=s' => \$dump_file,
    'planet=s' => \$planet_name,
    'config=s' => \$cfg_file,
    'help'     => \$help,
  );

  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

  usage() if ($help or !$planet_name);
  
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

# Get Storage
  my $distcent;
  for my $pid (keys %$planets) {
    my $curr_planet = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ("$curr_planet" eq "$planet_name"); # Test Planet

    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    print "$planet_name\n";

    $distcent  = first { defined($_) } grep { $buildings->{$_}->{url} eq '/distributioncenter' } keys %$buildings;
    last;
  }

  print "Distribution Center: ", $distcent,"\n";

  my $em_bit;
  print "Getting View\n";
  $em_bit = $client->building( id => $distcent, type => 'DistributionCenter' )->view();

  print OUTPUT $dumper->dump($em_bit);
  close(OUTPUT);

  print "RPC Count Used: $em_bit->{status}->{empire}->{rpc_count}\n";
exit;


sub usage {
  print "Figure it out!\n";
  exit;
}
