#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my @planets;

GetOptions(
    'planet=s@' => \@planets,
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
	 #debug    => 1,
);

my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# if no --planet args provided, run on all planets
if (!@planets ) {
    @planets = keys %planets;
}

for my $name (@planets) {
    # Load planet data
    my $body      = $client->body( id => $planets{$name} );
    my $result    = $body->get_buildings;
    my $buildings = $result->{buildings};
    
    my @park_id = grep {
            $buildings->{$_}->{name} eq 'Park'
    } keys %$buildings;
    
    for my $park_id (@park_id) {
        my $park = $client->building( id => $park_id, type => 'Park' );
        
        next unless $park->view->{party}{can_throw};
        
        $park->throw_a_party;
    }
}


sub usage {
  die <<"END_USAGE";
Usage: $0 throw_party.yml
       --planet       NAME

--planet can be passed multiple times.

If planet is not provided, will attempt to throw a party on all planets.

Throws a party in all parks on the planet(s).

END_USAGE

}
