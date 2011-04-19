#!/usr/bin/perl

## Junk building trash removal. Must have Junk Henge available to build.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util						(qw(max));
use Getopt::Long					(qw(GetOptions));
use Games::Lacuna::Client ();

	my $planet_name;
	my $x_loc = 5;
	my $y_loc = -5;

	GetOptions(
		'planet=s' => \$planet_name,
		'x=i' => \$x_loc,
		'y=i' => \$y_loc,
	);

	my $cfg_file = shift(@ARGV) || 'lacuna.yml';
	unless ( $cfg_file and -e $cfg_file ) {
		die "Did not provide a config file. got: $cfg_file";
	}

	my $client = Games::Lacuna::Client->new(
								 cfg_file => $cfg_file,
								 # debug		=> 1,
	);

# Load the planets
	my $empire	= $client->empire->get_status->{empire};
	my $planets = $empire->{planets};
	
	my $available_slots = 0;
	
	if($empire->{rpc_count} > 9000) {
		print "High RPC Count ($empire->{rpc_count}). Exiting.\n";
		exit 1;
	}

# Scan each planet
	foreach my $planet_id ( sort keys %$planets ) {
		my $name = $planets->{$planet_id};

		next if !($name eq $planet_name);

		print "Checking $x_loc,$y_loc on $name:\n";

		# Load planet data
		my $planet		= $client->body( id => $planet_id );
		my $result		= $planet->get_buildings;
		my $body			= $result->{status}->{body};
		
		my $buildings = $result->{buildings};

		my $buildable = $planet->get_buildable($x_loc, $y_loc, 'Happiness');
		my $bb = $buildable->{buildable};
		
		my $junk = $client->building( type => 'JunkHengeSculpture' );
		
		if (exists $bb->{'Junk Henge Sculpture'}) {
			while(1) {
				print "Junk Henge purging " . $bb->{'Junk Henge Sculpture'}->{build}->{cost}->{waste} . " trash, ";
				sleep 1;
				
				my $ok = eval {
					my $return = $junk->build($planet_id, $x_loc, $y_loc);
					print "blowing up junk.\n";
					$junk->demolish($return->{building}->{id});
				};
				unless($ok) {
					if (my $e = Exception::Class->caught('LacunaRPCException')) {
						print "done trash removal: $e\n";
						exit;
					}
					else {
						my $e = Exception::Class->caught();
						ref $e ? $e->rethrow : die "$e\n";
					}
				}
				
				sleep 10; # Server takes a few seconds to register demo
			}
		}
	}
	
exit;


sub usage {
	die <<"END_USAGE";
Usage: $0 CONFIG_FILE
		--planet		 PLANET

CONFIG_FILE	 defaults to 'lacuna.yml'

--planet is the planet you want to remove trash from.
--x is the x-coordinate of the building location, defaults to 5
--y is the y-coordinate of the building location, defaults to -5

It will loop until it cannot build another junk henge. If you already have a junk henge built, you must destory it before running this script.

END_USAGE

}

