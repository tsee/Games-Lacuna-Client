#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw(min max);
use List::MoreUtils       qw( uniq );
use Getopt::Long          qw(GetOptions);
use Games::Lacuna::Client ();
use JSON;

my $ships_per_page;
my @specs = qw( combat hold_size max_occupants speed stealth );
my %opts;
$opts{data} = "log/docked_ships.js";

GetOptions(
    \%opts,
    'planet=s@',
    'data=s',
    @specs,
    'travelling',
    'mining',
    'supply',
    'waste',
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
	cfg_file => $cfg_file,
        rpc_sleep => 2,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{colonies}{$_}, $_ } keys %{ $empire->{colonies} };

my $total_str     = 'Total Docks';
my $mining_str    = 'Ships Mining';
my $defend_str    = 'Ships on remote Defense';
my $supply_str    = 'Ships on Supply Chains';
my $waste_str     = 'Ships on Waste Chains';
my $available_str = 'Docks Available';
my $ttl_ships = 0;
my $ttl_docks = 0;
my @all_ships;
my $ship_hash = {};

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if ($opts{planet} and not (grep { $name eq $_ } @{$opts{planet}}));

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
    my $supply_count    = 0;
    my $waste_count     = 0;
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

    $ship_hash->{$name} = $ships;

    $supply_count +=
        grep {
            $_->{task} eq 'Supply Chain'
        } @$ships;
    
    $waste_count +=
        grep {
            $_->{task} eq 'Waste Chain'
        } @$ships;
    
    $mining_count +=
        grep {
            $_->{task} eq 'Mining'
        } @$ships;
    
    $defend_count +=
        grep {
            $_->{task} eq 'Defend'
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
    $ttl_docks += $space_port_status->{max_ships};
    
    printf "%${max_length}s: %d\n",
        $mining_str,
        $mining_count;
    
    if ( $supply_count ) {
        printf "%${max_length}s: %d\n",
            $supply_str,
            $supply_count
    }

    if ( $waste_count ) {
        printf "%${max_length}s: %d\n",
            $waste_str,
            $waste_count
    }

    if ( $defend_count ) {
        printf "%${max_length}s: %d\n",
            $defend_str,
            $defend_count
    }
    
    printf "%${max_length}s: %d\n",
        $available_str,
        $space_port_status->{docks_available};
    $ttl_ships += $space_port_status->{max_ships} - $space_port_status->{docks_available};
    
    push @all_ships, @$ships;
    
    print "\n";
}

print "Total number of ships: ", $ttl_ships, "\n";
print "Total number of docks: ", $ttl_docks, "\n";
print "Total space available: ", $ttl_docks-$ttl_ships,"\n\n";

print_ships( "Total Ships", \@all_ships )
    unless $opts{planet};

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);

  open(DUMP, ">", "$opts{data}") or die;
  print DUMP $json->pretty->canonical->encode($ship_hash);
  close(DUMP);

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
