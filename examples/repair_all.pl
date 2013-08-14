#!/usr/bin/env perl
#
# Simple program for repairing

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

  my %opts = (
        h         => 0,
        v         => 0,
        city      => 0,  #by default we don't repair cities because they take huge amounts of resources
        platforms => 0,  #by default we don't repair platforms
        config    => "lacuna.yml",
        dumpfile  => "log/repairs.js",
        station   => 0, # Don't repair station modules by default
        sleep     => 1, # Sleep 1 second between calls by default
  );

  GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'planet=s@',
    'config=s',
    'dumpfile=s',
    'ordered',
    'city',
    'platforms',
    'sleep',
    'station',
  );

  usage() if $opts{h};
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  open(OUTPUT, ">", $opts{dumpfile}) || die "Could not write to $opts{dumpfile}, you probably need to make a log directory.\n";

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  print "Starting RPC: $glc->{rpc_count}\n";

# Get planets
  my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
  $status->{planets} = \%planets;

  my $keep_going = 1;
  do {
    my $pname;
    my @skip_planets;
    for $pname (sort keys %planets) {
      if ($opts{planet} and not (grep { $pname eq $_ } @{$opts{planet}})) {
        push @skip_planets, $pname;
        next;
      }
      print "Inspecting $pname\n";
      my $planet    = $glc->body(id => $planets{$pname});
      my $result    = $planet->get_buildings;
      my $buildings = $result->{buildings};
      my $station = $result->{status}{body}{type} eq 'space station' ? 1 : 0;
      if ($station and !$opts{station}) {
        push @skip_planets, $pname;
        next;
      }
      my ($sarr) = bstats($buildings, $station);
      my @bids = map { $_->{id} } @$sarr;
      my $return = $planet->repair_list(\@bids);
      for my $bld (@$sarr) {
        my $cur = $return->{buildings}->{$bld->{id}}->{efficiency};
        my $old = $bld->{efficiency};
        $return->{buildings}->{$bld->{id}}->{efficiency_old} = $old;
        if ($old != $cur) {
          printf "%25s %2d/%2d repaired %3d percent to %3d percent.\n", $bld->{name}, $bld->{x}, $bld->{y}, $cur - $old, $cur;
        }
      }
      $status->{"$pname"} = $return->{buildings};
      print "Done with $pname\n";
      push @skip_planets, $pname;
    }
    print "Done with: ",join(":", sort @skip_planets), "\n";
    for $pname (@skip_planets) {
      delete $planets{$pname};
    }
    if (keys %planets) {
      print "Clearing Queue shouldn't be needed.\n";
      sleep 1;
    }
    else {
      print "Nothing Else to do.\n";
      $keep_going = 0;
    }
  } while ($keep_going);

 print OUTPUT $json->pretty->canonical->encode($status);
 close(OUTPUT);
 print "Ending   RPC: $glc->{rpc_count}\n";

exit;

sub bstats {
  my ($bhash, $station) = @_;

  my $bcnt = 0;
  my @sarr;
  for my $bid (keys %$bhash) {
    next if (($bhash->{$bid}->{name} =~ /Lost City/) && (!$opts{city}));
    next if (($bhash->{$bid}->{name} =~ /Platform/) && (!$opts{platforms}));
    my $ref = $bhash->{$bid};
    $ref->{id} = $bid;
    if ($ref->{repair_costs}) {
      push @sarr, $ref if ($ref->{efficiency} < 100);
    }
  }
  if ($opts{ordered}) {
    @sarr = sort { repair_cost($a->{repair_costs}) <=> repair_cost($b->{repair_costs}) ||
                 $b->{efficiency} <=> $a->{efficiency} ||
                 $a->{x} <=> $b->{x} ||
                 $a->{y} <=> $b->{y} } @sarr;
  }
  return (\@sarr);
}

sub repair_cost {
  my ($rhash) = @_;

#  print $json->pretty->canonical->encode($rhash);
# die;

  return ($rhash->{food} + $rhash->{water} + $rhash->{ore} + $rhash->{energy} );
}

sub sec2str {
  my ($sec) = @_;

  my $day = int($sec/(24 * 60 * 60));
  $sec -= $day * 24 * 60 * 60;
  my $hrs = int( $sec/(60*60));
  $sec -= $hrs * 60 * 60;
  my $min = int( $sec/60);
  $sec -= $min * 60;
  return sprintf "%04d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
}

sub get_type_from_url {
  my ($url) = @_;

  my $type;
  eval {
    $type = Games::Lacuna::Client::Buildings::type_from_url($url);
  };
  if ($@) {
    print "Failed to get building type from URL '$url': $@";
    return 0;
  }
  return 0 if not defined $type;
  return $type;
}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program upgrades spaceports on your planet. Faster than clicking each port.
It will upgrade in order of level up to maxlevel.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config <file>    - Specify a GLC config file, normally lacuna.yml.
  --planet <name>    - Specify planet
  --dumpfile         - data dump for all the info we don't print
  --ordered          - figure cheapest to most expensive.  Costs more RPC.
  --city             - Repair Lost City Pieces
  --platforms        - Repair Terra and Gas Platforms
  --station          - Repair Station Modules
  --sleep            - Sleep interval between api calls.
END
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}
