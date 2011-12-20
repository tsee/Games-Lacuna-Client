#!/usr/bin/perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use List::Util   qw( first );
use Date::Parse;
use Date::Format;
use utf8;

  my %opts = (
    h          => 0,
    v          => 0,
    config     => "lacuna.yml",
    datafile   => "data/data_blackhole.js",
    maxdist    => 300,
  );

  my $ok = GetOptions(\%opts,
    'planet=s',
    'x=i',
    'y=i',
    'id=i',
    'target=s',
    'help|h',
    'datafile=s',
    'config=s',
    'make_asteroid',
    'make_planet',
    'increase_size',
    'change_type=i',
    'swap_places',
    'view',
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
  usage() if ($opts{h});
  if (!$opts{planet}) {
    print "Need BHG planet set with --planet!\n";
    usage();
  }
  my $json = JSON->new->utf8(1);

  my $target_id;
  my $params = {};
  unless ($opts{view}) {
    if ($opts{change_type}) {
      if ($opts{change_type} < 1 or $opts{change_type} > 21) {
        print "New Type must be 1-21\n";
        usage();
      }
      else {
        $params->{newtype} = $opts{change_type};
        print "Changing to type $params->{newtype}\n";
      }
    }
    usage() if !$opts{target} && !defined $opts{x} && !defined $opts{y} && !defined $opts{id};

    usage() if defined $opts{x} && !defined $opts{y};
    usage() if defined $opts{y} && !defined $opts{x};
  }

  my $ofh;
  open($ofh, ">", $opts{datafile}) || die "Could not create $opts{datafile}";

  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config},
    # debug    => 1,
  );

  my $data  = $glc->empire->view_species_stats();
  my $ename = $data->{status}->{empire}->{name};
  my $ststr = $data->{status}->{server}->{time};

# reverse hash, to key by name instead of id
  my %planets = map { $data->{status}->{empire}->{planets}{$_}, $_ }
                  keys %{ $data->{status}->{empire}->{planets} };

# Load planet data
  my $body   = $glc->body( id => $planets{$opts{planet}} );

  my $result = $body->get_buildings;

  my ($x,$y) = @{$result->{status}->{body}}{'x','y'};
  my $buildings = $result->{buildings};

# Find the BHG
  my $bhg_id = first {
        $buildings->{$_}->{url} eq '/blackholegenerator'
  } keys %$buildings;

  die "No BHG on this planet\n"
	  if !$bhg_id;

  my $target; my $target_name;
  my $bhg =  $glc->building( id => $bhg_id, type => 'BlackHoleGenerator' );
  unless ($opts{view}) {
    if ( defined $opts{x} && defined $opts{y} ) {
      $target      = { x => $opts{x}, y => $opts{y} };
      $target_name = "$opts{x},$opts{y}";
    }
    elsif ( defined $opts{target} ) {
      $target      = { body_name => $opts{target} };
      $target_name = $opts{target};
    }
    elsif ( defined $opts{id} ) {
      $target      = { body_id => $opts{id} };
      $target_name = $opts{id};
    }
    else {
      die "target arguments missing\n";
    }
  }

  if ($bhg) {
    if ($opts{view}) {
      print "Viewing BHG: $bhg_id\n";
    }
    else {
      print "Targetting $target_name with $bhg_id\n";
    }
  }
  else {
    print "No BHG!\n";
  }

  my $bhg_out;
  if ($opts{view}) {
    $bhg_out = $bhg->view();
  }
  elsif ($opts{make_planet}) {
    $bhg_out = $bhg->generate_singularity($target, "Make Planet");
  }
  elsif ($opts{make_asteroid}) {
    $bhg_out = $bhg->generate_singularity($target, "Make Asteroid");
  }
  elsif ($opts{increase_size}) {
    $bhg_out = $bhg->generate_singularity($target, "Increase Size");
  }
  elsif ($opts{change_type}) {
    $bhg_out = $bhg->generate_singularity($target, "Change Type", $params);
  }
  elsif ($opts{swap_places}) {
    $bhg_out = $bhg->generate_singularity($target, "Swap Places");
  }
  else {
    die "Nothing to do!\n";
  }

  print $ofh $json->pretty->canonical->encode($bhg_out);
  close($ofh);

  if ($opts{view}) {
    print $json->pretty->canonical->encode($bhg_out->{tasks});
  }
  else {
    print $json->pretty->canonical->encode($bhg_out->{effect});
  }

#  print "$glc->{total_calls} api calls made.\n";
#  print "You have made $glc->{rpc_count} calls today\n";
exit; 

sub load_stars {
  my ($starfile, $range, $hx, $hy) = @_;

  open (STARS, "$starfile") or die "Could not open $starfile";

  my @stars;
  my $line = <STARS>;
  while($line = <STARS>) {
    my  ($id, $name, $sx, $sy) = split(/,/, $line, 5);
    $name =~ tr/"//d;
    my $distance = sqrt(($hx - $sx)**2 + ($hy - $sy)**2);
    if ( $distance < $range) {
      my $star_data = {
        id   => $id,
        name => $name,
        x    => $sx,
        y    => $sy,
        dist => $distance,
      };
      push @stars, $star_data;
    }
  }
  return \@stars;
}

sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --planet         PLANET_NAME
       --CONFIG_FILE    defaults to lacuna.yml
       --x              X coordinate of target
       --y              Y coordinate of target
       --id             id of target
       --target         target name of target (note you only need one of the 3 methods)
       --help|h         This help message
       --datafile       Output file, default data/data_blackhole.js
       --config         Lacuna Config, default lacuna.yml
       --make_asteroid  make an asteroid of target, only use against uninhabited planets
       --make_planet    make a planet of asteroid, only use against non-mined asteroids
       --increase_size  Increase size of habitable planet or asteroid
       --change_type    Change type of habitable planet
       --swap_places    Swap planet with targetted body
       --view           View options

END_USAGE

}
