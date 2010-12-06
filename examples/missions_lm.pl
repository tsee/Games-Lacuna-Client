#!/usr/bin/perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings::MissionCommand;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $mission_file = "data_missions.yml";
GetOptions(
  'o=s' => \$mission_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$mission_file") || die "Could not open $mission_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Embassies
  my @mission;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};

    my @sybit = grep { $buildings->{$_}->{name} eq 'Mission Command' } keys %$buildings;
    
    push @mission, @sybit;
  }

  print "MC IDs: ".join(q{, },@mission)."\n";

# Find mission
  my @builds;
  my $mc_bit;
  my $sy_id;
  for $sy_id (@mission) {
#    $mc_bit = $client->building( id => $sy_id, type => 'MissionCommand' )->skip_mission(18238);
#    $mc_bit = $client->building( id => $sy_id, type => 'MissionCommand' )->skip_mission(19130);
#    $mc_bit = $client->building( id => $sy_id, type => 'MissionCommand' )->skip_mission(14629);
    $mc_bit = $client->building( id => $sy_id, type => 'MissionCommand' )->get_missions();
    push @builds, $mc_bit;
  }
  print OUTPUT $dumper->dump(\@builds);
  close(OUTPUT);
