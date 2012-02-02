#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long					(qw(GetOptions));
use Games::Lacuna::Client ();
use List::Util qw( first max );

my $planet_name;
my $max;
my $help;

GetOptions(
	'planet=s' => \$planet_name,
    'max=i'    => \$max,
    'help|h'   => \$help,
);

usage() if $help;

die "--planet opt required\n"
    if !defined $planet_name;

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
    # debug		=> 1,
);

# Load the planets
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Load planet data
my $body = $client->body( id => $planets{$planet_name} );


do {
    my $buildings = $body->get_buildings->{buildings};

    # if --max isn't provided, find out how many plans we have
    $max ||= plan_count( $buildings );

    my $build_time = build_time( $buildings );

    if ( $build_time ) {
        $build_time += 5;
        print "Sleeping for $build_time while build queue empties\n";
        sleep $build_time;
    }

    my $queue_length = queue_length( $buildings );

    # fill build-queue
    for ( 1 .. $queue_length ) {
        exit if $max-- == 0;

        build_halls( $buildings );
    }

} while ( $max );

exit;


sub plan_count {
    my ( $buildings ) = @_;

    my $pcc = first {
        $buildings->{$_}{url} eq '/planetarycommand'
    } keys %$buildings;

    $pcc = $client->building( id => $pcc, type => 'PlanetaryCommand' );

    my $plans = $pcc->view_plans->{plans};

    my @halls = grep {
        $_->{name} eq 'Halls of Vrbansk'
    } @$plans;

    die "No Halls of Vrbansk plans available\n"
        if !@halls;

    return scalar @halls
}

sub build_time {
    my ( $buildings ) = @_;

    return
        max
        grep { defined }
        map {
            $_->{pending_build}{seconds_remaining}
        } values %$buildings;
}

sub queue_length {
    my ( $buildings ) = @_;

    my $id = first {
        $buildings->{$_}{url} eq '/development'
    } keys %$buildings;

    return 1 + $buildings->{$id}{level};;
}

sub build_halls {
    my ( $buildings ) = @_;

    my ( $x, $y ) = next_empty_plot( $buildings );

    die "No remaining empty spaces to build on\n"
        if !defined $x;

    my $vrbansk = $client->building( type => 'HallsOfVrbansk' );

    print "Building a Halls on $x,$y\n";

    my $status = $vrbansk->build( $planets{$planet_name}, $x, $y );

    # make sure we don't try building on the same plot later
    my $id = $status->{building}{id};
    $buildings->{$id}{x} = $x;
    $buildings->{$id}{y} = $y;

    return $status;
}

sub next_empty_plot {
    my ( $buildings ) = @_;

    for my $x ( -5 .. 5 ) {
        for my $y ( -5 .. 5 ) {
            next if grep {
                   $buildings->{$_}{x} == $x
                && $buildings->{$_}{y} == $y
            } keys %$buildings;

            return $x, $y;
        }
    }

    return;
}

sub usage {
	die <<"END_USAGE";
Usage: $0 CONFIG_FILE
	--planet   PLANET
    --max      MAX HALLS TO BUILD

CONFIG_FILE	 defaults to 'lacuna.yml'

Automates building Halls of Vrbansk plans on free plots.

END_USAGE

}

