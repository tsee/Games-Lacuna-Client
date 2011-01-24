#!/usr/bin/perl 
use strict;
use warnings;
use FindBin;
use Games::Lacuna::Client::Governor;
use Games::Lacuna::Client;
use YAML::Any;

# NOTE: If you are not already running the governor, running this script can be very expensive in terms
# of RPC calls, as it will have to pull buildings stats for every building.  Once this is done, it will
# be cached for cache_duration, but the initial startup cost is high.

$| = 1;

my $client_config   = '/path/to/your/config_file';

unless ( $client_config and -e $client_config ) {
  $client_config = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $client_config and -e $client_config ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new( cfg_file => $client_config );

$Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
my $governor = Games::Lacuna::Client::Governor->new( $client, {
    cache_dir => '/your/governor/cache/dir', # You will want to specify this.
    cache_duration => 86400,
    colony => { _default_ => { priorities => [] }, },
    verbosity => { summary => 1, production => 1 }
});

my $arg = shift @ARGV;
$governor->run();
