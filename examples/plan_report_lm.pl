#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use YAML;
use YAML::Dumper;
use Getopt::Long qw(GetOptions);

binmode STDOUT, ":utf8";

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

# my $decor = 0;

# GetOptions{
#  'p=s' => \$recipe_yml,
#  'decor' => \$decor,
# };

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
foreach my $name ( sort keys %planets ) {

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the Planetary Command
    my $pcc_id = first {
            $buildings->{$_}->{url} eq '/planetarycommand'
    } keys %$buildings;
    next unless $pcc_id;
    my $pcc   = $client->building( id => $pcc_id, type => 'PlanetaryCommand' );
    my $plans = $pcc->view_plans->{plans};
    
    next if !@$plans;
    
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    @$plans = sort { $a->{name} cmp $b->{name} } @$plans;
    
    for my $plan (@$plans) {
      printf "%s %d +%d\n",
        ucfirst($plan->{name}),
        $plan->{level},
        $plan->{extra_build_level};
    }
    print "\n";
}
