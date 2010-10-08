use strict;
use warnings;
use Games::Lacuna::Client;
use List::Util qw(min max sum);
use Data::Dumper;
use YAML::Any 'LoadFile';
use Getopt::Long qw(GetOptions);

use constant MINUTE => 60;

our $TimePerIteration = 10;

GetOptions(
  'i|interval=f' => \$TimePerIteration,
);
$TimePerIteration = int($TimePerIteration * MINUTE);

my $config_file = shift @ARGV;
if (not defined $config_file or not -e $config_file) {
  die "Usage: $0 myempire.yml";
}

my $cfg = LoadFile($config_file);

my $client = Games::Lacuna::Client->new(
  uri      => $cfg->{server_uri},
  api_key  => $cfg->{api_key},
  name     => $cfg->{empire_name},
  password => $cfg->{empire_password},
  #debug => 1,
);

#my $res = $client->alliance->find("The Understanding");
#my $id = $res->{alliances}->[0]->{id};

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my @planets = map $client->body(id => $_), keys %{$estatus->{planets}};

#print Dumper $client->alliance->view_profile( $res->{alliances}->[0]->{id} );

my $first_planet = $planets[0]; # Beware. I think these might contain asteroids, too.

# No, we don't generate objects from the big return value structs yet!
my %buildings = %{ $first_planet->get_buildings->{buildings} };

my @waste_ids = grep {$buildings{$_}{name} eq 'Waste Recycling Center'}
                keys %buildings;

# use the first only for now
my $wr = Games::Lacuna::Client::Buildings::WasteRecycling->new(
  client => $client,
  id     => $waste_ids[0]
);

while (1) {
  output("checking WR stats");
  my $wr_stat = $wr->view;

  my $busy_seconds = $wr_stat->{building}{work}{seconds_remaining};
  if ($busy_seconds) {
    output("Still busy for $busy_seconds, waiting");
    sleep $busy_seconds+3;
    if ($busy_seconds > 5*MINUTE) {
      $wr_stat = $wr->view;
    }
  }
  
  output("Checking resource stats");
  my $pstatus = $wr_stat->{status}{body} or die "Could not get planet status via \$struct->{status}{body}: " . Dumper($wr_stat);
  my $waste = $pstatus->{waste_stored};
  
  if (not $waste or $waste < 100) {
    output("(virtually) no waste has accumulated, waiting");
    sleep 5*MINUTE;
    next;
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
    $ore    = $rec_waste * 0.5*($water_s+$energy_s)/$total_s;
    $water  = $rec_waste * 0.5*($energy_s+$ore_s)/$total_s;
    $energy = $rec_waste * 0.5*($water_s+$ore_s)/$total_s;
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
  output("Recycling failed: $@") if $@;
 
  output("Waiting for recycling job to finish");
  sleep int($rec_waste*$sec_per_waste)+3;
}

sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}
