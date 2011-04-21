#!/usr/bin/perl
#
# Usage: probes.pl -h
#  

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use Date::Parse;
use Date::Format;
use YAML::XS;
use utf8;

my $probe_file = "data/probe_data_raw.yml";
my $cfg_file = "lacuna.yml";
my $help    = 0;

GetOptions(
  'output=s' => \$probe_file,
  'config=s' => \$cfg_file,
  'help' => \$help,
);
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
#    debug    => 1,
  );

  usage() if $help;

  my $fh;
  open($fh, ">", "$probe_file") || die "Could not open $probe_file";

  my $data = $glc->empire->view_species_stats();

# Get planets
  my $planets = $data->{status}->{empire}->{planets};
  my $ename   = $data->{status}->{empire}->{name};
  my $ststr   = $data->{status}->{server}->{time};
  my $stime   = str2time( map { s!^(\d+)\s+(\d+)\s+!$2/$1/!; $_ } $ststr);
  my $ttime   = ctime($stime);
  print "$ttime\n";

# Get obervatories;
  my @observatories;
  for my $pid (keys %$planets) {
    my $buildings = $glc->body(id => $pid)->get_buildings()->{buildings};
    push @observatories, grep { $buildings->{$_}->{url} eq '/observatory' } keys %$buildings;
  }

# Find stars
  my @stars;
  my @star_bit;
  for my $obs_id (@observatories) {
    my $obs_view  = $glc->building( id => $obs_id, type => 'Observatory' )->view();
    my $pages = 1;
    my $num_probed = 0;
    do {
      my $obs_probe = $glc->building( id => $obs_id, type => 'Observatory' )->get_probed_stars($pages++);
      $num_probed = $obs_probe->{star_count};
      @star_bit = @{$obs_probe->{stars}};
      if (@star_bit) {
        for my $star (@star_bit) {
          $star->{observatory} = {
            empire => $ename,
            oid    => $obs_id,
            pid    => $obs_probe->{status}->{body}->{id},
            pname  => $obs_probe->{status}->{body}->{name},
            stime  => $stime,
            ststr  => $ststr,
          }
        }
        push @stars, @star_bit;
      }
    } until (@star_bit == 0);
    printf "%-12s: %7d  Level: %2d, Probes: %2d of %2d\n", $obs_view->{status}->{body}->{name},
            $obs_id, $obs_view->{building}->{level}, $num_probed, $obs_view->{building}->{level} * 3;
    sleep 5;
  }

# Gather planet data
  my @bodies;
  my %bod_id;
  for my $star (@stars) {
    my @tbod;
    for my $bod ( @{$star->{bodies}} ) {
# Check for duplicated probes
      if (defined($bod_id{$bod->{id}})) {
        $bod_id{$bod->{id}} = $bod_id{$bod->{id}}.",".$star->{observatory}->{oid};
        printf "Probe dupe: %s %d : %s %s\n", $bod->{star_name}, $bod->{id},
                                              $bod_id{$bod->{id}}, $star->{observatory}->{pname};
      }
      else {
        $bod_id{$bod->{id}} = $star->{observatory}->{oid};
      }
      $bod->{observatory} = {
        empire => $star->{observatory}->{empire},
        oid    => $star->{observatory}->{oid},
        pid    => $star->{observatory}->{pid},
        pname  => $star->{observatory}->{pname},
        stime  => $star->{observatory}->{stime},
        ststr  => $star->{observatory}->{ststr},
        lastd  => 0,  # Initialize last Excavator time
        moved  => [ "nobody" ],
      };
      push @tbod, $bod;
    }
    push @bodies, @tbod if (@tbod);
  }

  YAML::Any::DumpFile($fh, \@bodies);
  close($fh);

  print "$glc->{total_calls} api calls made.\n";
  print "You have made $glc->{rpc_count} calls today\n";
exit;

sub usage {
    diag(<<END);
Usage: $0 [options]

This program takes all your data on observatories and places it in a YAML file for use by other programs.
Data contained is all the body data, plus which observatory "owns" the probe for this bit of data.
Stars may be repeated if multiple observatories probe the same star, but we will report that.  Note that abandoning either probe currently, abandons all probes at the star.


Options:
  --help                 - Prints this out
  --output <file>        - Output file, default: data/probe_data_raw.yml

END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
