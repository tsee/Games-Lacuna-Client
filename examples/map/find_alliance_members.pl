#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);

$| = 1;

my $config_file = shift @ARGV || 'lacuna.yml';
die if not defined $config_file or not -e $config_file;

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

my $rv = $client->alliance->find('The Understanding');
my $alliance = $rv->{alliances}[0];
die if not defined $alliance;

my $profile = $client->alliance(id => $alliance->{id})->view_profile();
my $members = $profile->{profile}{members};

open my $yml, '>', 'map.yml'
    or die "Unable to open map.yml for writing, $!\n";
print $yml "---\n";
print $yml "empire_id: $profile->{status}{empire}{id}\n";
print $yml "allied_empires: \n";
print $yml "  - $_->{id}\n" for @{ $members };
close $yml;

print "Successfully created map.yml\n";

