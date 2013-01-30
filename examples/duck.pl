#!/user/bin/perl

=head2
This script is designed to use as many RPCs as possible, so as to test GLC's handling of the Click Limit.
=cut

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long (qw(GetOptions));
use List::Util (qw(first));
use Data::Dumper; #debug

my ($name, $pass, $planet_name) = '';
GetOptions(
	"empire=s" => \$name,
	"pass=s"   => \$pass,
	"planet=s" => \$planet_name
);

# Initialize the GLC object.
my $glc = Games::Lacuna::Client->new(
	uri       => "https://us1.lacunaexpanse.com/",
	api_key   => "anonymous",
	name      => $name,
	password  => $pass
) or die ("Cannot connect to the server.\n");

# Find the planet.
my $planets = {reverse %{$glc->empire->get_status()->{empire}->{planets}}};
my $planet = $planets->{$planet_name};

my $buildings        = $glc->body(id => $planet)->get_buildings()->{buildings};
my $entertainment_id = first {
	$buildings->{$_}->{url} eq '/entertainment';
} keys %$buildings;
my $entertainment = $glc->building(id => $entertainment_id, type => 'entertainment');

my $count = 1;
for (;;) {
	print "Quacking the duck! :D $count\n";
	$entertainment->duck_quack();
	$count++;
}