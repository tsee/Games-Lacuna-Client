#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw(min max);
use List::MoreUtils       qw( uniq );
use Getopt::Long          qw(GetOptions);
use Games::Lacuna::Client ();
use JSON;

  my %opts;
  $opts{data} = "log/laws.js";
  $opts{config} = 'lacuna.yml';

  GetOptions(
    \%opts,
    'station_id=s',
    'data=s',
    'config=s',
  );

  open(DUMP, ">", "$opts{data}") or die "Could not write to $opts{data}\n";

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

  my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
        rpc_sleep => 2,
	# debug    => 1,
  );

# Load the planets
  my $empire  = $glc->empire->get_status->{empire};

  my $station = $glc->body( id => $opts{station_id});
  my $laws = $station->view_laws($opts{station_id});

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);

  print DUMP $json->pretty->canonical->encode($laws);
  close(DUMP);
exit;
