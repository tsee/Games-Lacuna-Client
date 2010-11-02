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

open my $fh, '<', $governor_config or die "Couldn't open $governor_config file";
my $config = YAML::Any::Load( do { local $/; <$fh> } );
close $fh;

$Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
my $governor = Games::Lacuna::Client::Governor->new( $client, $config );
my $arg = shift @ARGV;
$governor->run( defined $arg and $arg eq 'refresh' );

printf "%d total RPC calls this run.\n", $client->{total_calls};

exit;
