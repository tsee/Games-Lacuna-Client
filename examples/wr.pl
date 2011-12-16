#!/usr/bin/perl
use strict;
use warnings;
use 5.010000;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use List::Util qw(min max sum);
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use AnyEvent;

use constant MINUTE => 60;

our $TimePerIteration = 20;

my ($water_perc, $energy_perc, $ore_perc) = (0, 0, 0);
GetOptions(
  'i|interval=f' => \$TimePerIteration,
  'water=i' => \$water_perc,
  'ore=i'   => \$ore_perc,
  'energy=i'  => \$energy_perc,
);
$TimePerIteration = int($TimePerIteration * MINUTE);

if ($water_perc or $ore_perc or $energy_perc) {
	die "Percentages need to add up to 100\n" if $water_perc + $ore_perc + $energy_perc != 100;
	for ($water_perc, $ore_perc, $energy_perc) { $_ = $_ / 100; }
}

my $config_file = shift @ARGV || 'lacuna.yml';
unless ( $config_file and -e $config_file ) {
  $config_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  usage() unless $config_file and -e $config_file;
}

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

my $program_exit = AnyEvent->condvar;
my $int_watcher = AnyEvent->signal(
  signal => "INT",
  cb => sub {
    output("Interrupted!");
    undef $client;
    exit(1);
  }
);

#my $res = $client->alliance->find("The Understanding");
#my $id = $res->{alliances}->[0]->{id};

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
                      keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'


my @wrs;
foreach my $planet (values %planets_by_name) {
  my %buildings = %{ $planet->get_buildings->{buildings} };

  my @waste_ids = grep {$buildings{$_}{name} eq 'Waste Recycling Center'}
                  keys %buildings;
  push @wrs, map  { $client->building(type => 'WasteRecycling', id => $_) } @waste_ids;
}

my @wr_handlers;
my @wr_timers;
foreach my $iwr (0..$#wrs) {
  my $wr = $wrs[$iwr];
  push @wr_handlers, sub {
    my $wait_sec = update_wr($wr, $iwr);
    return if not $wait_sec;
    $wr_timers[$iwr] = AnyEvent->timer(
      after => $wait_sec,
      cb    => sub {
        output("Waited for $wait_sec on WR $iwr");
        $wr_handlers[$iwr]->()
      },
    );
  };
}

foreach my $wrh (@wr_handlers) {
  $wrh->();
}

output("Done setting up initial jobs. Waiting for events.");
$program_exit->recv;
undef $client; # for session persistence
exit(0);

sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}

sub usage {
  die <<"END_USAGE";
Usage: $0 myempire.yml
       --interval MINUTES  (defaults to 20)

Need to generate an API key at https://us1.lacunaexpanse.com/apikey
and create a configuration YAML file that should look like this

  ---
  api_key: the_public_key
  empire_name: Name of empire
  empire_password: password of empire
  server_uri: https://us1.lacunaexpanse.com/

END_USAGE

}

sub update_wr {
  my $wr = shift;
  my $iwr = shift;

  output("checking WR stats for WR $iwr");
  my $wr_stat = $wr->view;

  my $busy_seconds = $wr_stat->{building}{work}{seconds_remaining};
  if ($busy_seconds) {
    output("Still busy for $busy_seconds, waiting");
    return $busy_seconds+3;
  }

  output("Checking resource stats");
  my $pstatus = $wr_stat->{status}{body} or die "Could not get planet status via \$struct->{status}{body}: " . Dumper($wr_stat);
  my $waste = $pstatus->{waste_stored};

  if (not $waste or $waste < 100) {
    output("(virtually) no waste has accumulated, waiting");
    return 5*MINUTE;
  }

  my $sec_per_waste = $wr_stat->{recycle}{seconds_per_resource};
  die "seconds_per_resource not found" if not $sec_per_waste;

  my $rec_waste = min($waste, $TimePerIteration / $sec_per_waste, $wr_stat->{recycle}{max_recycle});

  # yeah, I know this is a bit verbose.
  my $ore_c    = $pstatus->{ore_capacity};
  my $water_c  = $pstatus->{water_capacity};
  my $energy_c = $pstatus->{energy_capacity};

  my $ore_s    = $pstatus->{ore_stored};
  my $water_s  = $pstatus->{water_stored};
  my $energy_s = $pstatus->{energy_stored};

  my $produce_ore    = $ore_c > $ore_s+1;
  my $produce_water  = $water_c > $water_s+1;
  my $produce_energy = $energy_c > $energy_s+1;
  my $total_s        = $ore_s + $water_s + $energy_s;

  my ($ore, $water, $energy);
  if (not $produce_ore and not $produce_energy and not $produce_water) {
    output("All storage full! Producing equal amounts of resources to keep waste low.");
    ($ore, $water, $energy) = map {$total_s/3} 1..3;
  }
  else {
    if ($water_perc or $energy_perc or $ore_perc) {
      $ore    = $rec_waste * $ore_perc;
      $water  = $rec_waste * $water_perc;
      $energy = $rec_waste * $energy_perc;
    } else {
      $ore    = $rec_waste * 0.5*($water_s+$energy_s)/$total_s;
      $water  = $rec_waste * 0.5*($energy_s+$ore_s)/$total_s;
      $energy = $rec_waste * 0.5*($water_s+$ore_s)/$total_s;
    }
    if (not $produce_ore) {
      output("Ore storage full! Producing no ore.");
      $water  += $ore/2;
      $energy += $ore/2;
      $ore = 0;
    }
    if (not $produce_water) {
      output("Water storage full! Producing no water.");
      $ore    += $water/2;
      $energy += $water/2;
      $water = 0;
    }
    if (not $produce_energy) {
      output("Energy storage full! Producing no energy.");
      $ore   += $energy/2;
      $water += $energy/2;
      $energy = 0;
    }
  }

  #my ($water, $ore, $energy) = map int($rec_waste/3), (1..3);
  output("RECYCLING $rec_waste waste to ore=$ore, water=$water, energy=$energy!");
  eval {
    #warn Dumper $wr->recycle(int($water), int($ore), int($energy), 0);
    $wr->recycle(int($water), int($ore), int($energy), 0);
  };
  output("Recycling failed: $@"), return(1*MINUTE) if $@;

  output("Waiting for recycling job to finish");
  return int($rec_waste*$sec_per_waste)+3;
}
