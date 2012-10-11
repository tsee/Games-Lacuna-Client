#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use List::Util   (qw(first));
use Getopt::Long (qw(GetOptions));
use DateTime;
use JSON;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use utf8;

my @planets;
my $cfg_file  = "lacuna.yml";
my $yard_file = "data/shipyards.js";
my $help      = 0;
my $stype;
my $number    = 0;
my $noreserve = 0;
my $time;
my $rpcsleep = 2;

GetOptions(
    'planet=s@' => \@planets,
    'config=s'  => \$cfg_file,
    'yards=s'   => \$yard_file,
    'type=s'    => \$stype,
    'help'      => \$help,
    'number=i'  => \$number,
    'noreserve' => \$noreserve,
    'time=i'    => \$time,
    'sleep=i'   => \$rpcsleep,
);

my $glc = Games::Lacuna::Client->new(
    cfg_file  => $cfg_file,
    rpc_sleep => $rpcsleep,

    # debug    => 1,
);

usage() if $help or scalar @planets == 0 or !$stype;

my @ship_types = ship_types();

my $ship_build = first { $_ =~ /$stype/ } @ship_types;

unless ($ship_build) {
    print "$stype is an unknown type!\n";
    exit;
}
print "Will try to build $ship_build\n";

my $json = JSON->new->utf8(1);
my $ydata;
if ( -e $yard_file ) {
    my $yf;
    my $lines;
    open( $yf, "$yard_file" ) || die "Could not open $yard_file\n";
    $lines = join( "", <$yf> );
    $ydata = $json->decode($lines);
    close($yf);
}
else {
    print "Can not load $yard_file\n";
    print "Create with get_buildings.pl, get_shipyards.pl, and some editing\n";
    exit;
}

my $rpc_cnt;
my $rpc_lmt;
my $beg_dt = DateTime->now;
my $end_dt = DateTime->now;
if ($time) {
    $end_dt->add( seconds => $time );

    #    print "$time\n";
    print "Builds start: ", $beg_dt->hms, "\n";
    print "Terminate at: ", $end_dt->hms, "\n";
}

# Get Yard data and verify we can build asked for ship
my $yhash = setup_yhash( $ydata, $time, $number, $noreserve, \@planets );

my $not_done  = 1;
my $resume_dt = DateTime->now;
my $sleep_flg = 0;

while ($not_done) {
    my @del_planet;
    $not_done = 0;
    my $check_dt = DateTime->now;
    if ($time) {
        if ( $check_dt > $end_dt ) {
            print "Finished Time duration\n";
            $not_done = 0;
            last;
        }
        if ( $sleep_flg && $resume_dt > $end_dt ) {
            print "Shipyards will be busy past scheduled end time\n";
            $not_done = 0;
            last;
        }
    }
    if ( $sleep_flg && $resume_dt > $check_dt ) {
        my $sleep_num = $resume_dt - $check_dt;
        my $sleep_sec =
          $sleep_num->in_units('hours') * 3600 +
          $sleep_num->in_units('minutes') * 60 +
          $sleep_num->in_units('seconds') + 5;
        if ( $sleep_sec > 0 ) {
            print "Sleeping ", $sleep_sec, " seconds\n";
            sleep($sleep_sec);
        }
        $sleep_flg = 0;
    }

#    else {
#       print "$sleep_flg : Check: ",$check_dt->hms, ", Resume: ",$resume_dt->hms, "\n";
#    }
    for my $planet ( keys %$yhash ) {
        $not_done = 1;
        unless ( defined( $yhash->{"$planet"}->{yards} ) ) {
            print "No yards to build with on $planet\n";
            push @del_planet, $planet;
            last;
        }
        if ( scalar @{ $yhash->{"$planet"}->{yards} } > 1 ) {
            print scalar @{ $yhash->{"$planet"}->{yards} },
              " Yards on $planet\n";
        }
        for my $yard ( @{ $yhash->{"$planet"}->{yards} } ) {
            if ( $yhash->{"$planet"}->{keels} >= $yhash->{"$planet"}->{bldnum} )
            {
                print $yhash->{"$planet"}->{keels}, " done for $planet\n";
                push @del_planet, $planet;
                last;
            }
            $check_dt = DateTime->now;
            printf "Yard: %8s on %s - ", $yard->{id}, $planet;
            if ( $yard->{resume} > $check_dt ) {
                my $wait_dur = $yard->{resume} - $check_dt;
                my $wait_sec =
                  $wait_dur->in_units('hours') * 3600 +
                  $wait_dur->in_units('minutes') * 60 +
                  $wait_dur->in_units('seconds') + 5;
                print "Busy for $wait_sec.\n";
                $yard->{ysleep} = 1;
                next;
            }
            my $bld_result;
            my $view_result;
            my $ships_building;
            $yard->{ysleep} = 0;
            my $ok;
            $ok =
              eval { $view_result = $yard->{yard_pnt}->view_build_queue(); };
            my $num_to_q = 0;

            if ($ok) {
                $num_to_q =
                  $yard->{maxq} - $view_result->{number_of_ships_building};
                if ( $num_to_q + $yhash->{"$planet"}->{keels} >
                    $yhash->{"$planet"}->{bldnum} )
                {
                    $num_to_q =
                      $yhash->{"$planet"}->{bldnum} -
                      $yhash->{"$planet"}->{keels};
                }
                if ( $num_to_q > 0 ) {
                    $ok = eval {
                        $bld_result =
                          $yard->{yard_pnt}
                          ->build_ship( $ship_build, $num_to_q );
                    };
                }
                else {
                    $ok = 1013;
                }
            }
            if ($ok) {
                $yhash->{"$planet"}->{keels} += $num_to_q;
                print "Queued up $ship_build : ",
                  $yhash->{"$planet"}->{keels}, " of ",
                  $yhash->{"$planet"}->{bldnum}, " at ", $planet, " ";
                $ships_building = $bld_result->{number_of_ships_building};
                if (   $ships_building >= $yard->{maxq}
                    && $yhash->{"$planet"}->{keels} <
                    $yhash->{"$planet"}->{bldnum} )
                {
                    print " We have $ships_building ships building.\n";
                    my $yrd_wait = $ships_building * $yard->{bldtime};
                    $yrd_wait = 60 if $yrd_wait < 60;
                    $yard->{resume} = DateTime->now;
                    $yard->{resume}->add( seconds => $yrd_wait );
                    $yard->{ysleep} = 1;
                    $resume_dt = $yard->{resume};
                }
                else {
                    if ( $yhash->{"$planet"}->{keels} >=
                        $yhash->{"$planet"}->{bldnum} )
                    {
                        print " ", $yhash->{"$planet"}->{keels},
                          " done for $planet\n";
                        $yard->{ysleep} = 0;
                        push @del_planet, $planet;
                        last;
                    }
                    print "\n";
                }
            }
            else {
                my $error = $@;
                if ( $error =~ /1009|1002|1011/ ) {
                    print $error, "\n";
                    push @del_planet, $planet;
                }
                elsif ( $error =~ /The server is offline/ ) {
                    print "Server is down, stopping builds.\n";
                    $not_done = 0;
                    last;
                }
                elsif ( $error =~ /1010/ ) {
                    if ( $error =~
                        /You have already made the maximum number of requests/ )
                    {
                        print "Out of RPCs for the day, take a walk.\n";
                        $not_done = 0;
                        last;
                    }
                    print $error, " taking a minute off.\n";
                    sleep(60);
                }
                elsif ( $error =~ /1013/ ) {
                    print " Queue Full\n";
                    for my $tyard ( @{ $yhash->{"$planet"}->{yards} } ) {
                        my $yrd_wait =
                          ( 10 > $tyard->{maxq} ? 10 : $tyard->{maxq} ) *
                          $tyard->{bldtime};
                        $yrd_wait = 60 if $yrd_wait < 60;
                        $tyard->{resume} = DateTime->now;
                        $tyard->{resume}->add( seconds => $yrd_wait );
                        $yard->{ysleep} = 1;
                        $resume_dt = $tyard->{resume};
                    }
                    last;    # Next planet
                }
                else {
                    print $error, "\n";
                }
            }
        }
    }
    if ($not_done) {
        for my $planet (@del_planet) {
            delete $yhash->{"$planet"};
        }
        $sleep_flg = 1;
        if ( scalar keys %$yhash < 1 ) {
            $sleep_flg = 0;
            $not_done  = 0;
            last;
        }

        #      print "Check: ", $check_dt->hms, "\n";
        for my $planet ( keys %$yhash ) {
            for my $yard ( @{ $yhash->{"$planet"}->{yards} } ) {

#          printf "%s %d: f:%s ys:%s %s\n", $planet, $yard->{id}, $sleep_flg,
#                                           $yard->{ysleep}, $yard->{resume}->hms;
                if ( $yard->{ysleep} ) {
                    $resume_dt = $yard->{resume}
                      if $yard->{resume} < $resume_dt;
                }
                else {
                    $sleep_flg = 0;
                }
            }
        }

        #      print "Resume: ", $resume_dt->hms, "\n";
    }
    unless ( keys %$yhash ) {
        $not_done = 0;
    }
}
print "$glc->{rpc_count} RPC\n";
undef $glc;
exit;

sub setup_yhash {
    my ( $ydata, $time, $number, $noreserve, $planets ) = @_;

    my $planet;
    my $yhash;
    for $planet ( sort @$planets ) {
        $yhash->{"$planet"}->{keels}   = 0;
        $yhash->{"$planet"}->{reserve} = 0;
        $yhash->{"$planet"}->{bldnum}  = 0;

        for my $yid ( keys %{ $ydata->{"$planet"} } ) {
            next unless $ydata->{"$planet"}->{"$yid"}->{level} > 0;

            my $yard = {
                id     => $yid,
                maxq   => 0,
                resume => DateTime->now,
                ysleep => 0,
            };
            if ( defined( $ydata->{"$planet"}->{"$yid"}->{maxq} ) ) {
                next unless $ydata->{"$planet"}->{"$yid"}->{maxq} > 0;
                $yard->{maxq} = $ydata->{"$planet"}->{"$yid"}->{maxq};
            }
            else {
                $yard->{maxq} = $ydata->{"$planet"}->{"$yid"}->{level};
            }
            unless ( defined( $ydata->{"$planet"}->{"$yid"}->{reserve} ) ) {
                $ydata->{"$planet"}->{"$yid"}->{reserve} = 0;
            }
            if ($noreserve) {
                $yhash->{"$planet"}->{reserve} = 0;
            }
            else {
                if ( $ydata->{"$planet"}->{"$yid"}->{reserve} >
                    $yhash->{"$planet"}->{reserve} )
                {
                    $yhash->{"$planet"}->{reserve} =
                      $ydata->{"$planet"}->{"$yid"}->{reserve};
                }
            }

            unless ($ydata->{"$planet"}->{"$yid"}->{level} > 0
                and $ydata->{"$planet"}->{"$yid"}->{name} eq "Shipyard" )
            {
                print "Yard data error! ",
                  $ydata->{"$planet"}->{"$yid"}->{name},
                  " : ", $ydata->{"$planet"}->{"$yid"}->{level}, ".\n";
                die;
            }
            $yard->{yard_pnt} =
              $glc->building( id => $yid, type => "Shipyard" );
            my $buildable = $yard->{yard_pnt}->get_buildable();

            $yhash->{"$planet"}->{dockspace} =
              $buildable->{docks_available} - $yhash->{"$planet"}->{reserve};
            if ( $yhash->{"$planet"}->{dockspace} < 0 ) {
                $yhash->{"$planet"}->{dockspace} = 0;
            }

            if ( $buildable->{status}->{body}->{name} ne "$planet" ) {
                print STDERR "Mismatch of name! ",
                  $buildable->{status}->{body}->{name},
                  "not equal to ", $planet, "\n";
                die;
            }

            $rpc_cnt = $buildable->{status}->{empire}->{rpc_count};
            $rpc_lmt = $buildable->{status}->{server}->{rpc_limit};

            #      last if ($yhash->{"$planet"}->{dockspace} == 0);
            if (
                (
                    $buildable->{docks_available} -
                    $yhash->{"$planet"}->{reserve}
                ) <= 0
              )
            {
                print "Nothing to build on ", $planet,
                  ". You have ", $buildable->{docks_available},
                  " dockspace left with a reserve of ",
                  $yhash->{"$planet"}->{reserve}, ".\n";
                last;
            }

            unless ( $buildable->{buildable}->{"$ship_build"}->{can} ) {
                print "$planet Can not build $ship_build : ",
                  @{ $buildable->{buildable}->{"$ship_build"}->{reason} }, "\n";
                die;
            }

            $yard->{bldtime} =
              $buildable->{buildable}->{"$ship_build"}->{cost}->{seconds};

            if ( $number == 0 or $yhash->{"$planet"}->{dockspace} < $number ) {
                $yhash->{"$planet"}->{bldnum} =
                  $yhash->{"$planet"}->{dockspace};
            }
            else {
                $yhash->{"$planet"}->{bldnum} = $number;
            }
            unless ( $yard->{maxq} == 0 ) {
                push @{ $yhash->{"$planet"}->{yards} }, $yard;
            }
        }

        if ( $yhash->{"$planet"}->{bldnum} <= 0 ) {
            delete $yhash->{"$planet"};
        }
        else {
            print "$planet: We hope to build ", $yhash->{"$planet"}->{bldnum},
              " with a reserve of ", $yhash->{"$planet"}->{reserve},
              " and dockspace of ",
              $yhash->{"$planet"}->{dockspace}, "\n";
        }
    }
    print "With Setup: RPC ", $rpc_cnt, " of ", $rpc_lmt, " Limit\n";

    return $yhash;
}

sub usage {
    diag(<<END);
Usage: $0 --planet <planet> --type <shiptype> [options]


Options:
  --help               - Prints this out
  --config    cfg_file   - Config file, defaults to lacuna.yml
  --planet    planet     - Planet Names you are building at.
  --yards     file       - File with shipyard level & ID default data/shipyards.js
  --type      shiptype   - ship type you want to build, partial name fine
  --number    number     - Number of ships you wish to produce at each shipyard
  --noreserve            - Ignore Reserve number in datafile
  --time      number     - Run for number of seconds
END
    exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
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
          supply_pod2
          supply_pod4
          surveyor
          sweeper
          terraforming_platform_ship
          thud
          ),
    );
    return @shiptypes;
}
