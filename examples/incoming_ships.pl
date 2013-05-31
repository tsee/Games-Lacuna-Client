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
    outfile      => $log_dir . '/incoming_ships.js',
  );

  my $ok = GetOptions(\%opts,
    'config=s',
    'outfile=s',
    'v|verbose',
    'h|help',
    'planet=s',
    'dump',
  );

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
  my $output;
  if ($opts{dump}) {
    open($df, ">", "$opts{outfile}") or die "Could not open $opts{outfile} for writing\n";
  }

  usage() if $opts{h} || !$opts{planet} || !$ok;

#  my $gorp;
#  usage() unless ( $gorp = select_something(\%opts) );

  my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
        rpc_sleep => 1,
	 #debug    => 1,
  );

  my $json = JSON->new->utf8(1);

  my $empire  = $glc->empire->get_status->{empire};
  my $planets = $empire->{planets};

# reverse hash, to key by name instead of id
  my %planets_by_name = map { $planets->{$_}, $_ } keys %$planets;

  my $p_id = $planets_by_name{$opts{planet}}
    or die "--planet $opts{planet} not found";

# Load planet data
  my $body      = $glc->body( id => $planets_by_name{ "$opts{planet}" } );
  my $buildings = $body->get_buildings->{buildings};

# Find the Police or Spaceport
  my $inc_id = first {
        $buildings->{$_}->{name} eq 'Police Station' or
        $buildings->{$_}->{name} eq 'Space Port'
  }
  grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
  keys %$buildings;

  die "No Police or Space Port!" unless $inc_id;
  print $buildings->{$inc_id}->{name}, " found.\n";
  my $inc_pt;
  if ($buildings->{$inc_id}->{name} eq "Police Station") {
    $inc_pt = $glc->building( id => $inc_id, type => "PoliceStation" );
  }
  elsif ($buildings->{$inc_id}->{name} eq "Space Port") {
    $inc_pt = $glc->building( id => $inc_id, type => "SpacePort" );
  }
  else {
    die $buildings->{$inc_id}->{name}, " invalid.\n";
  }
  die unless $inc_pt;

  my @incoming;
  my $page = 1;
  while ($page) {
    my $ship_list;
    my $return = eval {
                  $ship_list = $inc_pt->view_foreign_ships($page);
              };
    if ($@) {
      print "$@ error!\n";
      sleep 60;
    }
    else {
      push @incoming, @{$ship_list->{ships}};
      if ($page == 1) {
        $output->{number_of_ships} = $ship_list->{number_of_ships};
      }
      if (@{$ship_list->{ships}} < 25) {
        print "$page. Done\n";
        $page = 0;
      }
      else {
        print $page, ", ";
        $page++;
      }
    }
  }

  if ( !@incoming) {
    print "No ships incoming to $opts{planet}\n";
  }
  else {
    $output->{ships} = \@incoming;
    print $output->{number_of_ships}, " incoming ships!\n";
    for my $income (@incoming) {
      my $from = "?";
      if ($income->{from}->{empire}) {
        $from = sprintf("%s:%d %s:%d",
                  $income->{from}->{empire}->{name},
                  $income->{from}->{empire}->{id},
                  $income->{from}->{name},
                  $income->{from}->{id});
      }
      printf("%25s %25s %20s from %s\n",
            $income->{type_human},
            $income->{date_arrives},
            $income->{name},
            $from);
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
Usage: $0 --planet PLANET

  --planet  Planet or Space Station to see incoming
  --dump    Output results into json file in log directory
  --outfile Default log/incoming_ships.js
END_USAGE

}

