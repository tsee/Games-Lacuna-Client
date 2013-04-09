#!/usr/bin/env perl

use strict;
use warnings;
use List::Util qw( first max );
use List::MoreUtils qw( any none );
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
	'config'    => "lacuna.yml",
);

GetOptions(\%opts,
	'planet|colony=s@',
	'max-level|maxlevel=i',
	'config=s',
	'pause=i',
	'attempts=i',
	'skip-platforms',
	'skip-if-busy',
	'queue',
	'single-level',
	'help',
	'verbose',
);

usage() if $opts{help};

my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
);

# Load the planets
my $empire = $glc->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

PLANET:
for my $planet_name ( keys %planets ) {
	if ( $opts{planet} ) {
		next PLANET if none { lc $planet_name eq lc $_ } @{ $opts{planet} };
	}
	
	print "Planet: $planet_name\n";
	
	# Load planet data
	my $planet = $glc->body( id => $planets{$planet_name} );
	my $devmin;
	my $queue;
	my $first_upgrade_level;
	
	for my $level ( 1 .. $opts{'max-level'}-1 ) {
		my $status    = $planet->get_buildings;
		my $buildings = $status->{buildings};
		
		if ( $level == 1 && $status->{status}{body}{type} eq 'space station' ) {
			print "Skipping Space Station\n"
				if $opts{verbose};
			
			next PLANET;
		}
		
		# check for builds-in-progress before we start
		my ( $pending_build ) =
			max
			grep { $_ }
			map { $buildings->{$_}{pending_build}{seconds_remaining} }
				keys %$buildings;
		
		if ( $pending_build && $opts{'skip-if-busy'} && $level == 1 ) {
			print "Already something building - honouring --skip-if-busy\n";
			next PLANET;
		}
		elsif ( $opts{queue} ) {
			if ( !$devmin ) {
				$devmin = get_dev_min( $glc, $buildings )
					or next PLANET;
				
				$queue = get_dev_min_queue_space( $devmin );
			}
			
			if ( $first_upgrade_level && $first_upgrade_level != $level ) {
				print "Finished upgrading --single-level buildings\n";
				next PLANET;
			}
		}
		elsif ( $pending_build ) {
			printf "Already a build in-progress: will sleep for %d seconds\n", $pending_build;
			
			sleep $pending_build + $opts{pause};
			
			# refresh building levels
			$buildings = $planet->get_buildings->{buildings};
		}
		
BUILDING:
		for my $id ( sort keys %$buildings ) {
			if ( $opts{queue} && !$queue ) {
				print "No space left in Development build queue\n";
				next PLANET;
			}
			
			my $building = $buildings->{$id};
			
			next BUILDING if $building->{level} != $level;
			
			my $type = building_type_from_label( $building->{name} );
			
			if ( $opts{'skip-platform'} && $type =~ /Platform$/ ) {
				printf "Skipping platform: %s\n", _building( $building )
					if $opts{verbose};
				
				next BUILDING;
			}
			
			if ( any { $_ eq 'glyph' } get_tags( $type ) ) {
				printf "Skipping glyph building: %s\n", _building( $building )
					if $opts{verbose};
				
				next BUILDING;
			}
			
			if ( any { $_ eq 'sculpture' } get_tags( $type ) ) {
				printf "Skipping sculpture: %s\n", _building( $building )
					if $opts{verbose};
				
				next BUILDING;
			}
			
			if ( $building->{efficiency} != 100 ) {
				printf "Skipping: %s, efficiency @ %s%%\n",
					_building($building),
					$building->{efficiency}
					if $opts{verbose};
				
				next BUILDING;
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
			
			if ( $opts{queue} ) {
				$first_upgrade_level ||= $level;
				
				$queue--;
			}
			else {
				my $build_time = $status->{building}{pending_build}{seconds_remaining};
				
				printf "Will sleep for %d seconds while upgrade completes\n", $build_time;
				
				sleep $build_time + $opts{pause};
			}
		}
	}
}

sub get_dev_min {
	my ( $glc, $buildings ) = @_;
	
	my $id = first {
        $buildings->{$_}{url} eq "/development"
    } keys %$buildings;

    if ( !$id ) {
        print "--queue opt provided, but no Development Ministry found!\n";
        return;
    }

    return $glc->building( id => $id, type => "Development" );
}

sub get_dev_min_queue_space {
	my ( $devmin ) = @_;
	
	my $status = $devmin->view;
	
	my $max   = 1 + $status->{building}{level};
	my $taken = scalar @{ $status->{build_queue} };
	
	return $max - $taken;
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
		1 or more allowed. If not provided, will process all non-SS colonies.

	--max-level LEVEL
		Defaults to 29.

	--pause SECONDS
		Time to wait after each upgrade. Default to 3.

	--attempts ATTEMPTS
		Number of times to try each upgrade in case of failure. Defaults to 3.

	--skip-platforms
		Don't upgrade Terraforming and Gas Giant Platforms. Default true.

	--skip-if-busy
		Skip planet if there are already any builds/upgrades in process.
		Suitable for running under `cron` to avoid multiple processes
		attempting to upgrade the same building.
		Default false.

	--queue
		Fill the Development build queue with upgrades, and then exit.
		Default false

	--single-level
		Only for use in combination with the --queue opt.
		If true, will only queue upgrades for buildings at the same level as
		the first upgrade queued.
		Example: There are 4 buildings at level L2, L2, L3, L4: if the
		Development build queue has 4 empty slots, the default behaviour is
		to queue all 4 buildings for upgrade, in order of the lowest current
		level first.
		If --single-level is provided, it will instead only queue the 2 L2
		buildings for upgrade, and then exit.
		This may be useful if you have high-level buildings which you don't
		want upgraded until all the other lower-level buildings are upgraded
		first.
		Default false.

	--config CONFIG_FILE
		Defaults to 'lacuna.yml' in the current directory.

	--verbose

	--help
		Show help message.

END_USAGE

}
