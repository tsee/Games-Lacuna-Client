#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use List::Util   qw( first );
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my $planet;
my $spy_id;
my $spy_name;
my $affinity;
my $help;

GetOptions(
    'planet=s'   => \$planet,
    'id=i'       => \$spy_id,
    'name=s'     => \$spy_name,
	'affinity=s' => \$affinity,
	'help|h'     => \$help,
);

usage() if $help;
usage() if !$planet;
usage() if $spy_id && $spy_name;
usage() if ( ( $spy_id || $spy_name ) && !$affinity );

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
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Load planet data
my $body   = $client->body( id => $planets{$planet} );
my $result = $body->get_buildings;

my $buildings = $result->{buildings};

# Find the GeneticsLab
my $genlab_id = first {
        $buildings->{$_}->{url} eq '/geneticslab'
} keys %$buildings;

die "No Genetics Lab on this planet\n"
	if !$genlab_id;

my $genlab = $client->building( id => $genlab_id, type => 'GeneticsLab' );

my $return = $genlab->prepare_experiment;

die "no spies available\n"
	if !$return->{grafts};

my @grafts = @{ $return->{grafts} };

die "No spies available\n"
	if !@grafts;


if ( $spy_id || $spy_name ) {
	if ( $spy_id ) {
		@grafts = grep {
			$_->{spy}{id} eq $spy_id
		} @grafts;
	}
	else {
		@grafts = grep {
			lc( $_->{spy}{name} ) eq lc( $spy_name )
		} @grafts;
	}
	
	die "Spy graft not found\n"
		if !@grafts;
	
	die "More than 1 spy graft matched - suggest using --id instead\n"
		if @grafts > 1;
	
	$affinity = lc $affinity;
	
	my @affinity = grep {
		lc($_) =~ /^$affinity/
	} @{ $grafts[0]->{graftable_affinities} };
	
	die "Graftable affinity not found\n"
		if !@affinity;
	
	if ( @affinity > 1 ) {
		print "Matched more than 1 graftable affinity\n";
		print map { "$_\n" } @affinity;
		exit;
	}
	
	my $result;
	eval {
		$result = $genlab->run_experiment( $grafts[0]->{spy}{id}, $affinity[0] );
	};
	
	die "Fatal error: $@\n"
		if $@;
	
	printf "%s\n\n", $result->{experiment}{message};
}
else {
	print "Grafts available\n\n";

	for my $graft ( @grafts ) {
		printf "ID: %d\n", $graft->{spy}{id};
		printf "Name: %s\n", $graft->{spy}{name};
		
		print "Species:\n";
		map {
			printf "\t%s : %s\n", $_, $graft->{species}{$_}
		} sort keys %{ $graft->{species} };
		
		print "Graftable Affinities:\n";
		map {
			printf "\t%s\n", $_;
		} sort @{ $graft->{graftable_affinities} };
		
		print "\n";
	}
	
	printf "Graft odds: %d\n",    $return->{graft_odds};
	printf "Survival odds: %d\n", $return->{survival_odds};
	printf "Essentia cost: %d\n", $return->{essentia_cost};
}


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet PLANET_NAME
    --id       SPY_ID
    --name     SPY_NAME
    --affinity AFFINITY

CONFIG_FILE  defaults to 'lacuna.yml'

If no arguments are provided, it will print a list of available grafts.

To run an experiment, either --id or --name must be supplied.

--name will not be accepted if it matches more than 1 available spy - in this
case use --id instead.

--affinity only needs to match enough of the affinity to be unique.
e.g. "--affinity decep" will match "deception_affinity".

END_USAGE

}
