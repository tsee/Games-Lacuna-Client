#!/usr/bin/perl

use strict;
use warnings;
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
my $cfg_file;

if ($ARGV[0] !~ /^--/) {
	$cfg_file = shift @ARGV;
}
else {
	$cfg_file = 'lacuna.yml';
}

unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my @planets;

GetOptions(
    'planet=s@' => \@planets,
);

usage() if !@planets;

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

for my $name (@planets) {
    # Load planet data
    my $body      = $client->body( id => $planets{$name} );
    my $result    = $body->get_buildings;
    my $buildings = $result->{buildings};
    
    # Find the first Park
    my $park_id = first {
            $buildings->{$_}->{name} eq 'Park'
    } keys %$buildings;
    
    my $park = $client->building( id => $park_id, type => 'Park' );
    
    next unless $park->view->{party}{can_throw};
    
    $park->throw_a_party;
}


sub usage {
  die <<"END_USAGE";
Usage: $0 throw_party.yml
       --planet       NAME  (required)

--planet can be passed multiple times.

END_USAGE

}
