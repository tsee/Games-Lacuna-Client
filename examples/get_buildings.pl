#!/usr/bin/env perl
#
# A program that just spits out all buildings with location

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

  my %opts = (
        h => 0,
        v => 0,
        config => "lacuna.yml",
        dumpfile => "data/data_builds.js",
        layout => 0,
        station => 0,
        sleep   => 2,
        shipyard => 0,
        shipfile => "data/shipyards.js",
        layfile  => "data/layout.js",
  );

  GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'planet=s@',
    'config=s',
    'dumpfile=s',
    'layout',
    'layfile=s',
    'sleep',
    'station',
    'shipyard',
    'shipfile=s',
  );

  usage() if $opts{'h'};
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{'config'} || "lacuna.yml",
    rpc_sleep => $opts{'sleep'},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  if ($opts{shipyard} ne '0') {
    open(OUTPUT, ">", $opts{'shipfile'}) || die "Could not open $opts{'shipfile'}";
  }
  else {
    open(OUTPUT, ">", $opts{'dumpfile'}) || die "Could not open $opts{'dumpfile'}";
  }
  if ($opts{layout}) {
    open(LAYOUT, ">", $opts{'layfile'}) || die "Could not open $opts{'layfile'}";
  }

  my $status;
  my $layout;
  my $empire = $glc->empire->get_status->{empire};

# Get planets
  my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
  $status->{planets} = \%planets;

  for my $pname (keys %planets) {
    next if ($opts{planet} and not (grep { $pname eq $_ } @{$opts{planet}}));
    verbose("Inspecting $pname\n");
    my $planet    = $glc->body(id => $planets{$pname});
    my $result    = $planet->get_buildings;
#    if ($result->{status}{body}{type} eq 'space station' && !$opts{'station'}) {
#      verbose("Skipping Space Station: $pname\n");
#      next;
#    }
    my $buildings = $result->{buildings};
    my @keys = (keys %$buildings);
    my @layout;
    for my $bldid (@keys) {
      $buildings->{$bldid}->{leveled} = $buildings->{$bldid}->{level};
      if ($opts{shipyard}) {
        if ( $buildings->{$bldid}->{name} ne 'Shipyard' ) {
          delete $buildings->{$bldid};
        }
        else {
          $buildings->{$bldid}->{maxq} = $buildings->{$bldid}->{level};
          $buildings->{$bldid}->{reserve} = 10;
        }
      }
      if ($opts{layout}) {
        push @layout, { id => $bldid,
                        name => $buildings->{$bldid}->{name},
                        x => $buildings->{$bldid}->{x},
                        y => $buildings->{$bldid}->{y},
                      };
      }
    }
    if ($opts{layout}) {
      @layout = sort {$a->{x} <=> $b->{x} || $a->{y} <=> $b->{y}} @layout;
      $layout->{$pname} = \@layout;
    }
    $status->{$pname} = $buildings;
  }

  if ($opts{layout}) {
    print LAYOUT $json->pretty->canonical->encode($layout);
    close(LAYOUT);
  }
  print OUTPUT $json->pretty->canonical->encode($status);
  close(OUTPUT);

exit;


sub usage {
    diag(<<END);
Usage: $0 [options]

This program just gets an inventory of the buildings on your planets.
Use parse_building.pl to output a csv of the file.
leveled is a field inserted for use by an autobuild program. (still being developed)

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config <file>    - Specify a GLC config file, normally lacuna.yml.
  --planet <name>    - Specify planet
  --dumpfile         - data dump for all the info we don't print
  --station          - include space stations in listing
  --shipyard         - instead, output a shipyard file for use of build_ships.pl
  --shipfile         - Default shipyards.js
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
    my ($pname) = @_;

    $pname =~ s/\W//g;
    $pname = lc($pname);
    return $pname;
}
