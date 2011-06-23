#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();


my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my $status = $client->empire->get_status;

my %out = (
    time => 'Server Time',
    version => 'Version',
    rpc_limit => 'RPC Limit',
);

print <<OUT;
Server time: $status->{server}{time}
Version:     $status->{server}{version}
RPC limit:   $status->{server}{rpc_limit}
Map size x:  $status->{server}{star_map_size}{x}[0] to $status->{server}{star_map_size}{x}[1]
Map size y:  $status->{server}{star_map_size}{y}[0] to $status->{server}{star_map_size}{y}[1]

Empire:           $status->{empire}{name}
RPCs used today:  $status->{empire}{rpc_count}
Essentia balance: $status->{empire}{essentia}
OUT
