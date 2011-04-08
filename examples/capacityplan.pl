#!/usr/bin/perl 
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use List::Util            ();
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

use constant MINUTE => 60;
use constant HOUR   => 3600;

# API call count
my $i = 0;
my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
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
print ++$i . " - Loading empire $client->{name}...\n";
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Potential build options
my @options = ();

# Scan each planet
foreach my $name ( sort keys %planets ) {
    next if defined $planet_name && $planet_name ne $name;

	print ++$i . " - Loading planet $name...\n";

	# Load planet data
	my $planet    = $client->body( id => $planets{$name} );
	my $result    = $planet->get_buildings;
	my $body      = $result->{status}->{body};
	my $buildings = $result->{buildings};

	# Find the Development Ministry
	my $development_id = List::Util::first {
		$buildings->{$_}->{name} eq 'Development Ministry'
	} keys %$buildings;
	my $development_slots = $development_id
		? ($buildings->{$development_id}->{level} + 1)
		: 1;

	# How many remaining build slots are there?
	my $pending_build = scalar grep { $_->{pending_build} } values %$buildings;
	my $can_build     = $development_slots - $pending_build;

    # space-stations don't generate/store waste
    my @types = $body->{type} eq 'space station' ? qw( food ore water energy )
              :                                    qw( food ore water energy waste );
    
	# Analysis
	foreach my $type ( @types ) {
		my $capacity = $body->{"${type}_capacity"} || 0;
		my $stored   = $body->{"${type}_stored"}   || 0;
		my $hour     = $body->{"${type}_hour"}     || 0;
		my $storage  = $capacity - $stored;
		my $time     = $hour == 0 ? 0 : int( $capacity / $hour );
		my $left     = $hour == 0 ? 0 : int( $storage  / $hour );
		my $label    = ucfirst($type);

		if ( $hour < 0 ) {
			my $left = int( (0-$stored) / $hour );
			print "$name - $label - Negative production - Reaches zero in ${left}h\n";
			next;
		}

		# Is there a building we can upgrade?
		my $building = {
			food   => 'Food Reserve',
			ore    => 'Ore Storage Tanks',
			water  => 'Water Storage Tank',
			energy => 'Energy Reserve',
			waste  => 'Waste Sequestration Well',
		}->{$type};

		my @upgrade = grep {
			$_->{name} eq $building
			and not
			$_->{pending_build}
		} values %$buildings;
		my @already = grep {
			$_->{name} eq $building
			and
			$_->{pending_build}
		} values %$buildings;

		print "$name - $label - ${time}h capacity, ${left}h left";
		print " UPGRADING..." if @already;
		print "\n";

		next unless $can_build;
		next unless @upgrade;
		next if     @already;
		next if $time   < 0;
		next if $left   < 0;
		next if $stored <= 0;
		if ( $time > 10 and $left > 10 ) {
			next;
		}

		# Save as an option
		push @options, {
			planet   => $planets{$name},
			name     => $name,
			type     => $type,
			capacity => $capacity,
			stored   => $stored,
			hour     => $hour,
			time     => $time,
			left     => $left,
			label    => $label,
			upgrade  => \@upgrade,
		};
	}
}

# Print build options in order 
@options = sort {
	$a->{time} > $b->{time}
	or
	$a->{left} > $b->{left}
} @options;

# Print out the options
my $n = 0;
print "\n\n";
print "Recommended Storage Capacity Upgrades\n";
print "-------------------------------------\n";
foreach my $option ( @options ) {
	print 'Option ' . ++$n . " - $option->{name} - $option->{label} - $option->{time}h capacity, $option->{left}h left\n";
}

exit(0);

sub output {
	my $str = join ' ', @_;
	$str .= "\n" if $str !~ /\n$/;
	print "[" . localtime() . "] " . $str;
}
