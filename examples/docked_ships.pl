#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw(min max);
use Getopt::Long          qw(GetOptions);
use Games::Lacuna::Client ();

my $ships_per_page;
my @specs = qw( combat hold_size max_occupants speed stealth );
my %opts;

GetOptions(
    \%opts,
    'planet=s',
    @specs,
    'travelling',
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
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

my $available = 'Docks Available';
my @all_ships;

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if defined $opts{planet} && $opts{planet} ne $name;

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the first Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;
    
    next if !$space_port_id;
    
    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );
    
    my $ship_count;
    my $page = 1;
    my @ships;
    
    do {
        my $return    = $space_port->view_all_ships( $page );
        $ship_count ||= $return->{number_of_ships};
        my $ships     = $return->{ships};
        
        if ( $opts{all} ) {
            push @ships, @$ships;
        }
        else {
            my $task = $opts{travelling} ? 'Travelling'
                     :                     'Docked';
            
            push @ships, grep { $_->{task} eq $task } @$ships;
        }
        
        $ship_count -= scalar @$ships;
        $page++;
    }
    while ( $ship_count > 0 );
    
    my $max_length = print_ships( $name, \@ships );
    
    printf "%${max_length}s: %d\n",
        $available,
        $space_port->view->{docks_available};
    
    push @all_ships, @ships;
    
    print "\n";
}

print_ships( "Total Ships", \@all_ships )
    unless $opts{planet};

exit;


sub print_ships {
    my ( $name, $ships ) = @_;    
    
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    my $max_length = max( map { length $_->{type_human} } @$ships )
                   || 0;
    
    $max_length = length($available) > $max_length ? length $available
                :                                    $max_length;
    
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
            
            my $min = min( keys %{ $type{$type}{$spec} } );
            my $max = max( keys %{ $type{$type}{$spec} } );
            
            if ( $min == $max ) {
                print " $spec: $min";
            }
            else {
                print " $spec: $min-$max";
            }
        }
        
        print "\n";
    }
    
    return $max_length;
}
