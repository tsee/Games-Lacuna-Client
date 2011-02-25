#!/usr/bin/perl 
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client::Governor;
use Games::Lacuna::Client;
use YAML::Any;

$| = 1;

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

my $governor_config = shift(@ARGV) || 'governor.yml';
unless ( $governor_config and -e $governor_config ) {
            die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    #debug    => 1,
);

if ( $^O !~ /MSWin32/) {
    $Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
}

my $governor = Games::Lacuna::Client::Governor->new( $client, $governor_config );
my $arg = shift @ARGV;
$governor->run( defined $arg and $arg eq 'refresh' );

printf "%d total RPC calls this run.\n", $client->{total_calls};

exit;
