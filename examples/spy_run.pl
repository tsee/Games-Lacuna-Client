#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long          qw(GetOptions);
use List::Util            qw( first );
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my $planet_name;
my $target;
my $assignment;

GetOptions(
    'from=s'       => \$planet_name,
    'target=s'     => \$target,
    'assignment=s' => \$assignment,
);

usage() if !$planet_name || !$target || !$assignment;

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
	prompt_captcha => 1,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my $body      = $client->body( id => $planets{$planet_name} );
my $buildings = $body->get_buildings->{buildings};

my $intel_id = first {
        $buildings->{$_}->{url} eq '/intelligence'
} keys %$buildings;

my $intel = $client->building( id => $intel_id, type => 'Intelligence' );
my @spies;

for my $spy ( @{ $intel->view_spies->{spies} } ) {
    next if lc( $spy->{assigned_to}{name} ) ne lc( $target );

    my @missions = grep {
        $_->{task} =~ /^$assignment/i
    } @{ $spy->{possible_assignments} };

    next if !@missions;

    if ( @missions > 1 ) {
        warn "Supplied --assignment matches multiple possible assignments - skipping!\n";
        for my $mission (@missions) {
            warn sprintf "\tmatches: %s\n", $mission->{task};
        }
        last;
    }

    $assignment = $missions[0]->{task};

    push @spies, $spy;
}

for my $spy (@spies) {
    my $return;

    eval {
        $return = $intel->assign_spy( $spy->{id}, $assignment );
    };

    if ($@) {
        warn "Error: $@\n";
        next;
    }

    printf "%s\n\t%s\n",
        $return->{mission}{result},
        $return->{mission}{reason};
}

exit;


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --from       PLANET
    --target     PLANET
    --assignment MISSION

CONFIG_FILE  defaults to 'lacuna.yml'

--from is the planet that your spy is from.

--target is the planet that your spy is assigned to.

--assignment must match one of the missions listed in the API docs:
    http://us1.lacunaexpanse.com/api/Intelligence.html

It only needs to be long enough to uniquely match a single available mission,
e.g. "gather op" will successfully match "Gather Operative Intelligence"

END_USAGE

}
