#!/usr/bin/perl
#
# Just a proof of concept to make sure dump works for each storage

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

#  my $space_station = "Regulus Lex";
  my $space_station = "Tromso";


  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

  my $dump_file = "data/data_parliament.yml";
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

  my $output ="";
  my $parl;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ($planet_name eq "$space_station"); # Test Planet
    print "$planet_name\n";

    my @bit = grep { $buildings->{$_}->{name} eq 'Parliament' } keys %$buildings;
    $parl = $bit[0] if @bit;
    last;
  }

  my @out;
#  $output = $client->building( id => $parl, type => 'Parliament' )->view_propositions();
#  push @out, $output;
  $output = $client->building( id => $parl, type => 'Parliament' )->cast_vote(1, "yes");
  push @out, $output;
  $output = $client->building( id => $parl, type => 'Parliament' )->cast_vote(2, "yes");
  push @out, $output;
  $output = $client->building( id => $parl, type => 'Parliament' )->cast_vote(3, "yes");
  push @out, $output;

  print OUTPUT $dumper->dump(\@out);
  close(OUTPUT);

  print "RPC Count Used: ";
  if ($output) {
    print "$output->{status}->{empire}->{rpc_count} \n";
  }
