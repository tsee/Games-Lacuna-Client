#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw(min max);
use List::MoreUtils       qw( none uniq );
use Getopt::Long          qw(GetOptions);
use Games::Lacuna::Client ();

my $ships_per_page;
my @specs = qw( combat hold_size max_occupants speed stealth );
my %opts;

GetOptions(
    \%opts,
    'planet=s@',
    @specs,
    'travelling',
    'mining',
    'all',
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
	cfg_file  => $cfg_file,
    rpc_sleep => 2,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my $total_str     = 'Total Docks';
my $mining_str    = 'Ships Mining';
my $defend_str    = 'Ships on remote Defense';
my $excavator_str = 'Ships Excavating';
my $available_str = 'Docks Available';
my @all_ships;

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if defined $opts{planet} && none { lc $name eq lc $_ } @{ $opts{planet} };

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    next if $result->{status}{body}{type} eq 'space station';

    # Find the first Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    }
      grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
      keys %$buildings;

    next if !$space_port_id;

    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

    my $mining_count    = 0;
    my $defend_count    = 0;
    my $excavator_count = 0;
    my $filter;

    push @{ $filter->{task} }, 'Mining'
        if $opts{mining};

    push @{ $filter->{task} }, 'Travelling'
        if $opts{travelling};

    my $ships = $space_port->view_all_ships(
        {
            no_paging => 1,
        },
        $filter ? $filter : (),
    )->{ships};

    $mining_count +=
        grep {
            $_->{task} eq 'Mining'
        } @$ships;

    $defend_count +=
        grep {
            $_->{task} eq 'Defend'
        } @$ships;

    $excavator_count +=
        grep {
               $_->{task} eq 'Travelling'
            && $_->{type} eq 'excavator'
        } @$ships;

    @$ships =
        grep {
            $_->{task} eq 'Docked'
        } @$ships;

    my $max_length = print_ships( $name, $ships );

    my $space_port_status = $space_port->view;

    print "\n";

    printf "%${max_length}s: %d\n",
        $total_str,
        $space_port_status->{max_ships};

    printf "%${max_length}s: %d\n",
        $mining_str,
        $mining_count;

    if ( $defend_count ) {
        printf "%${max_length}s: %d\n",
            $defend_str,
            $defend_count
    }

    if ( $excavator_count ) {
        printf "%${max_length}s: %d\n",
            $excavator_str,
            $excavator_count
    }

    printf "%${max_length}s: %d\n",
        $available_str,
        $space_port_status->{docks_available};

    push @all_ships, @$ships;

    print "\n";
}

print_ships( "Total Ships", \@all_ships )
    unless $opts{planet} && @{ $opts{planet} } == 1;

exit;


sub print_ships {
    my ( $name, $ships ) = @_;

    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";

    my $max_length = max( map { length $_->{type_human} } @$ships )
                   || 0;

    $max_length = length($defend_str) > $max_length ? length $defend_str
                :                                     $max_length;

    my %type;

    for my $ship (@$ships) {
        my $type = $ship->{type_human};

        no warnings 'uninitialized';
        $type{$type}{count}++;

        for my $spec (@specs) {
            my $value = $ship->{$spec};

            no warnings 'uninitialized';
            $type{$type}{$spec}{$value}++;
        }
    }

    for my $type ( sort keys %type ) {
        printf "%${max_length}s: %d", $type, $type{$type}{count};

        for my $spec (@specs) {
            next if !$opts{$spec};

            print " ($spec: ";

            print
                join ", ",
                map {
                    sprintf "%dx %d",
                        $type{$type}{$spec}{$_},
                        $_
                } uniq sort keys %{ $type{$type}{$spec} };

            print ")";
        }

        print "\n";
    }

    return $max_length;
}
