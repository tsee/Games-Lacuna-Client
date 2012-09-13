#!/usr/bin/perl

use strict;
use warnings;
use List::Util qw( max );
use List::MoreUtils qw( any );
use Getopt::Long qw(GetOptions);
use Try::Tiny;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Games::Lacuna::Client::Types qw( building_type_from_label get_tags );

$| = 1;

my %opts = (
	'max-level' => 29,  # I know 30 is max, but for planets with a lot of spaceports, too much energy
	'pause'     => 3,
	'attempts'  => 3,
	config      => "lacuna.yml",
);

GetOptions(\%opts,
	'planet|colony=s',
	'max-level|maxlevel=i',
	'config=s',
	'pause=i',
	'attempts=i',
	'skip-platforms',
	'exit-if-busy',
	'help',
	'verbose',
);

usage() if $opts{help};
usage() if !exists $opts{planet};

my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
);

# Load the planets
my $empire  = $glc->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

for my $planet_name ( keys %planets ) {
	next if lc $planet_name ne lc $opts{planet};
	
	print "Planet: $planet_name\n";
	
	# Load planet data
	my $planet = $glc->body( id => $planets{$planet_name} );
	
	for my $level ( 1 .. $opts{'max-level'}-1 ) {
		my $buildings = $planet->get_buildings->{buildings};
		
		# check for builds-in-progress before we start
		my ( $pending_build ) =
			max
			grep { $_ }
			map { $buildings->{$_}{pending_build}{seconds_remaining} }
				keys %$buildings;
		
		if ( $pending_build ) {
			if ( $level == 1 && $opts{'exit-if-busy'} ) {
				print "Already something building - honouring --exit-if-busy\n";
				exit;
			}
			
			printf "Already a build in-progress: will sleep for %d seconds\n", $pending_build;
			
			sleep $pending_build + $opts{pause};
			
			# refresh building levels
			$buildings = $planet->get_buildings->{buildings};
		}
		
BUILDING:
		for my $id ( sort keys %$buildings ) {
			my $building = $buildings->{$id};
			
			next if $building->{level} != $level;
			
			my $type = building_type_from_label( $building->{name} );
			
			if ( $opts{'skip-platform'} && $type =~ /Platform$/ ) {
				printf "Skipping platform: %s\n", _building( $building )
					if $opts{verbose};
				
				next;
			}
			
			if ( any { $_ eq 'glyph' } get_tags( $type ) ) {
				printf "Skipping glyph building: %s\n", _building( $building )
					if $opts{verbose};
				
				next;
			}
			
			if ( any { $_ eq 'sculpture' } get_tags( $type ) ) {
				printf "Skipping sculpture: %s\n", _building( $building )
					if $opts{verbose};
				
				next;
			}
			
			if ( $building->{efficiency} != 100 ) {
				printf "Skipping: %s, efficiency @ %s%%\n",
					_building($building),
					$building->{efficiency}
					if $opts{verbose};
				
				next;
			}
			
			printf "Will upgrade %s\n", _building( $building );
			
			my $status;
ATTEMPT:
			for ( 1..3 ) {
				try {
					$status = $glc->building( id => $id, type => $type )->upgrade;
				}
				catch {
					printf "Upgrade failed: %s\n", $_;
				};
				last ATTEMPT if $status;
			}
			
			next BUILDING if !$status;
			
			my $build_time = $status->{building}{pending_build}{seconds_remaining};
			
			printf "Will sleep for %d seconds while upgrade completes\n", $build_time;
			
			sleep $build_time + $opts{pause};
		}
	}
}

sub _building {
	my ($b) = @_;
	
	return sprintf "%s L%d (%d,%d)",
		$b->{name},
		$b->{level},
		$b->{x},
		$b->{y};
}

sub usage {
    my ($message) = @_;

    $message = $message ? "$message\n\n" : '';

    die <<"END_USAGE";
${message}Usage: $0 [opts]

	--planet PLANET-NAME
		Required. Single argument. No default.

	--max-level LEVEL
		Defaults to 29.

	--pause SECONDS
		Time to wait after each upgrade. Default to 3.

	--attempts ATTEMPTS
		Number of times to try each upgrade in case of failure. Defaults to 3.

	--skip-platforms
		Don't upgrade Terraforming and Gas Giant Platforms. Default true.

	--exit-if-busy
		Exit immediately if there are already any builds/upgrades in process.
		Suitable for running under `cron` to stop multiple processes attempting
		to upgrade the same building.
		Default false.

	--config CONFIG_FILE
		Defaults to 'lacuna.yml' in the current directory.

	--verbose

	--help
		Show help message.

END_USAGE

}
