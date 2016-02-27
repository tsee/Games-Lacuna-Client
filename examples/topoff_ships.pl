#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
use POSIX                 (qw(floor));
use DateTime;
use Date::Parse;
use Date::Format;
use JSON;
use utf8;

  my $random_bit = int rand 9999;
  my $data_dir = 'data';
  my $log_dir  = 'log';

  my %opts = (
    h            => 0,
    v            => 0,
    config       => "lacuna.yml",
    dump         => 0,
    outfile      => $log_dir . '/topoff_ships.js',
    minlevel     => 30,
    maxqueue     => 600,
    sleep        => 1,
  );

  my $ok = GetOptions(\%opts,
    'config=s',
    'outfile=s',
    'v|verbose',
    'h|help',
    'planet=s@',
    'dump',
    'type=s',
    'maintain=i',
    'number=i',
    'minlevel=i',
    'maxqueue=i',
    'sleep=i',
    'mining',
    'chain',
    'trade',
    'travel',
    'orbit',
    'all',
  );

  usage() unless $ok;
  usage() if $opts{help} or !$opts{planet} or !$opts{type};
  usage() unless ($opts{number} or $opts{maintain});

  my @ship_types = ship_types();

  my $ship_build = first { $_ =~ /^$opts{type}/i } @ship_types;

  unless ($ship_build) {
    print "$opts{type} is an unknown type!\n";
    exit;
  }
  print "Will try to build $ship_build\n";

  unless ( $opts{config} and -e $opts{config} ) {
    $opts{config} = eval{
      require File::HomeDir;
      require File::Spec;
      my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
      File::Spec->catfile(
        $dist,
        'login.yml'
      ) if $dist;
    };
    unless ( $opts{config} and -e $opts{config} ) {
      die "Did not provide a config file";
    }
  }
  my $df;
  my $output = {};
  if ($opts{dump}) {
    open($df, ">", "$opts{outfile}") or die "Could not open $opts{outfile} for writing\n";
  }

  usage() if $opts{h} || !$ok;

  my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
        rpc_sleep => $opts{sleep},
	 #debug    => 1,
  );

  my $json = JSON->new->utf8(1);

  my $empire  = $glc->empire->get_status->{empire};
  my $planets = $empire->{colonies};

# reverse hash, to key by name instead of id
  my %planets = map { $planets->{$_}, $_ } keys %$planets;

  PLANET:
  foreach my $pname (sort keys %planets) {
    next PLANET if ($opts{planet} and not (grep { $pname eq $_ } @{$opts{planet}}));
    my $planet = $glc->body( id => $planets{$pname} );
    my $buildings = $planet->get_buildings->{buildings};
    my $sp_id = first {
                        $buildings->{$_}->{name} eq 'Space Port'
                      }
                grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
                keys %$buildings;
    unless ($sp_id) {
      print "No Spaceport on $pname.\n";
      next PLANET;
    }
    my $sp_pt = $glc->building( id => $sp_id, type => "SpacePort" );
    next PLANET unless $sp_pt;
    my $ship_list;
    my $paging = {
      no_paging => 1,
    };
    my $filter = {
      task => [ "Docked", "Building" ],
      type => "$ship_build",
    };
    if ($opts{mining}) {
      push @{$filter->{task}}, "Mining";
    }
    if ($opts{chain}) {
      push @{$filter->{task}}, "Waste Chain", "Supply Chain";
    }
    if ($opts{trade}) {
      push @{$filter->{task}}, "Waiting on Trade";
    }
    if ($opts{travel}) {
      push @{$filter->{task}}, "Travelling";
    }
    if ($opts{orbit}) {
      push @{$filter->{task}}, "Defend", "Orbiting";
    }
    if ($opts{all}) {
      delete $filter->{task};
    }
    my $return = eval {
                  $ship_list = $sp_pt->view_all_ships($paging, $filter);
              };
    
    my $maintain = 0;
    if (defined($opts{maintain})) {
      $maintain = $opts{maintain};
    }
    if ($@) {
      print "$@ error!\n";
      next PLANET;
#      sleep 60;
    }
    else {
      $output->{"$pname"}->{ship_list} = $return;
      printf("%4d ships of type %s found on planet %s.\n", $return->{number_of_ships}, $ship_build, $pname);
      if ($opts{number}) {
        if ($maintain) {
          if ($maintain > $return->{number_of_ships} + $opts{number}) {
            $maintain = $return->{number_of_ships} + $opts{number};
          }
        }
        else {
          $maintain = $return->{number_of_ships} + $opts{number};
        }
      }
    }
    if ($maintain > $return->{number_of_ships}) {
      my $build_num = $maintain - $return->{number_of_ships};
      print "Will try building $build_num on $pname\n";
      my @sy_id = grep { $buildings->{$_}->{name} eq 'Shipyard' and
                       $buildings->{$_}->{level} >= $opts{minlevel} and
                       $buildings->{$_}->{efficiency} == 100
                       } keys %$buildings;
      unless (@sy_id) {
        print "No Shipyards on $pname of at least level $opts{minlevel}.\n";
        next PLANET;
      }
      my $buildables;
      my $buildq;
      my $queued_ships = 0;
      SHIPYARD:
      for my $sy_id ( sort {$buildings->{$b}->{level} <=> $buildings->{$a}->{level} } @sy_id) {
        my $sy_pt = $glc->building( id => $sy_id, type => "Shipyard" );
        my $return = eval {
                       $buildables = $sy_pt->get_buildable();
        };
        if ($@) {
          print "$@ error!\n";
          next SHIPYARD;
        }
        $output->{"$pname"}->{buildables}->{$sy_id} = $return;
        unless ($buildables->{buildable}->{$ship_build}->{can} == 1) {
          printf("Can not build %s at Shipyard: %s skipping planet!\n%s\n", $ship_build, $sy_id, 
                 join(":",@{$buildables->{buildable}->{$ship_build}->{reason}}));
          next PLANET;
        }
        $return = eval {
                    $buildq = $sy_pt->view_build_queue();
        };
        if ($@) {
          print "$@ error!\n"; #Better error handling needed.
          next SHIPYARD;
        }
        $output->{"$pname"}->{buildq}->{$sy_id} = $return;
        my $ships_to_queue = $build_num - $queued_ships;
        my $maxqueue = $buildables->{build_queue_max} - $buildables->{build_queue_used};
        if ($ships_to_queue > $buildables->{docks_available}) {
          $ships_to_queue = $buildables->{docks_available};
        }
        if ($ships_to_queue > $opts{maxqueue}) {
          $ships_to_queue = $opts{maxqueue};
        }
        if ($ships_to_queue > $opts{maxqueue} - $buildq->{number_of_ships_building}) {
          $ships_to_queue = $opts{maxqueue} - $buildq->{number_of_ships_building};
        }
        if ($ships_to_queue > $maxqueue) {
          $ships_to_queue = $maxqueue;
        }
        if ($ships_to_queue > 0) {
          my $built;
          $return = eval {
                       $built = $sy_pt->build_ship($ship_build, $ships_to_queue);
          };
          if ($@) {
            print "$@ error!\n"; #Better error handling needed.
            next SHIPYARD;
          }
          else {
            $queued_ships += $ships_to_queue;
          }
          if ($queued_ships >= $build_num) {
            print "Done with $pname.\n";
            next PLANET;
          }
        }
#    "docks_available" : 7,         # you can only build ships up to the number of docks you have available
#    "build_queue_max" : 60,        # maximum queueable ships
#    "build_queue_used" : 3
      }
      printf "Queued %3d %s ships on %s\n",$queued_ships, $ship_build, $pname;
    }
    else {
      print "Already at $return->{number_of_ships} $ship_build on $pname\n";
    }
  }
  if ($opts{dump}) {
    print $df $json->pretty->canonical->encode($output);
    close($df);
  }
  print "$glc->{total_calls} api calls made.\n";
  print "You have made $glc->{rpc_count} calls today\n";
exit;

sub usage {
  die <<END_USAGE;
Usage: $0 --planet PLANET --number NUMBER --maintain NUMBER

  --planet    planet     - Planets to check (multiple allowed)
  --dump                 - Output results into json file in log directory
  --outfile   file       - Default log/excav_replace.js
  --maintain  number     - What number of the type of ships to have docked in spaceport.
  --type      shiptype   - ship type you want to build, partial name fine.
  --number    number     - Number of ships you wish to produce.
  --minlevel  number     - Minimum Level of Shipyard to use. default 30.
  --maxqueue  number     - Maximum to put into any queue. default 50.
  --sleep     number     - RPC Sleep delay
  --mining               - Include ships on mining to count toward maintanance
  --chain                - Include ships on waste or supply chains to count toward maintanance
  --trade                - Include ships involved with trades.
  --travel               - Include ships travelling.
  --orbit                - Include ships orbiting or defending.
  --all                  - All ships of type are included in current count.

Note, this will not continue running and will only pass thru your shipyards once.  If you want to build more than your shipyards can do in one iteration,
please see build_ships.pl or use a scheduler.

Examples:
  $0 --planet DOCKS --maintain 20 --number 10 --maxqueue 5 --type excav
Will build excavators, up to 10 if number of excavs on DOCKS is less than 20.  It will build at most 5 per shipyard.

  $0 --planet DOCKS --number 60 --maxqueue 20 --type snark3
Will build sixty snark3 ships regardless of how many are currently at DOCKS. Will build 20 at each shipyard until number is reached.

END_USAGE

    my @ship_types = ship_types();
    print "\nShip types: ", join(", ", sort @ship_types ),"\n";
    exit 1;
}

sub ship_types {

    my @shiptypes = (
        qw(
          barge
          bleeder
          cargo_ship
          colony_ship
          detonator
          dory
          drone
          excavator
          fighter
          fissure_sealer
          freighter
          galleon
          gas_giant_settlement_ship
          hulk
          hulk_fast
          hulk_huge
          mining_platform_ship
          observatory_seeker
          placebo
          placebo2
          placebo3
          placebo4
          placebo5
          placebo6
          probe
          scanner
          scow
          scow_fast
          scow_large
          scow_mega
          security_ministry_seeker
          short_range_colony_ship
          smuggler_ship
          snark
          snark2
          snark3
          spaceport_seeker
          space_station
          spy_pod
          spy_shuttle
          stake
          supply_pod
          supply_pod2
          supply_pod3
          supply_pod4
          supply_pod5
          surveyor
          sweeper
          terraforming_platform_ship
          thud
          ),
    );
    return @shiptypes;
}
