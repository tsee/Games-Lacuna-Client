#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my $planet_name;
my $demolish;

GetOptions(
    'planet=s' => \$planet_name,
    'demolish' => \$demolish,
);

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

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Scan each planet
for my $name ( sort keys %planets ) {

    next if defined $planet_name && $planet_name ne $name;

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;

    my $buildings = $result->{buildings};

    # Find the Deployed Bleeders
    my @bleeders = grep {
            $buildings->{$_}->{url} eq '/deployedbleeder'
    } keys %$buildings;

    if (@bleeders) {
        printf "%s has %d deployed bleeders\n", $name, scalar(@bleeders);

        if ($demolish) {
            for my $id (@bleeders) {
                my $bleeder = $client->building( id => $id, type => 'DeployedBleeder' );

                $bleeder->demolish;
            }

            print "All bleeders on planet demolished\n";
        }

        print "\n";
    }
}

