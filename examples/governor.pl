#!/usr/bin/perl 
use strict;
use warnings;
use Games::Lacuna::Client::Governor;
use Games::Lacuna::Client;
use YAML::Any;

$| = 1;

my $client_config   = '/path/to/client_config.yml';
my $governor_config = '/path/to/governor_config.yml';

my $client = Games::Lacuna::Client->new( cfg_file => $client_config );

$Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
my $governor = Games::Lacuna::Client::Governor->new( $client, $governor_config );
my $arg = shift @ARGV;
$governor->run( defined $arg and $arg eq 'refresh' );

printf "%d total RPC calls this run.\n", $client->{total_calls};

exit;
