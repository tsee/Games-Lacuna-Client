#!/usr/bin/perl

use strict;
use warnings;
use List::Util            qw( first max );
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

my %my_trades;

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the Trade Ministry
    my $trade_id = first {
            $buildings->{$_}->{name} eq 'Trade Ministry'
    } keys %$buildings;
    
    # Find the Subspace Transporter
    my $transporter_id = first {
            $buildings->{$_}->{name} eq 'Subspace Transporter'
    } keys %$buildings;
    
    
    if ($trade_id) {
        my $trade = $client->building( id => $trade_id, type => 'Trade' );
        
        my $trades = $trade->view_my_trades;
        
        if ( $trades->{trade_count} ) {
            $my_trades{$name}{'Trade Ministry'} = $trades->{trades};
        }
    }
    
    if ($transporter_id) {
        my $transporter = $client->building( id => $transporter_id, type => 'Transporter' );
        
        my $trades = $transporter->view_my_trades;
        
        if ( $trades->{trade_count} ) {
            $my_trades{$name}{'Subspace Transporter'} = $trades->{trades};
        }
    }
}

for my $name (sort keys %my_trades) {
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    for my $building (sort keys %{ $my_trades{$name} }) {
        printf "%s\n", $building;
        
        my @trades = @{ $my_trades{$name}{$building} };
        
        my $max_length = max map { length $_->{offer_description} } @trades;
        
        for my $trade (@trades) {
            printf "Offering %-${max_length}s for %s\n",
                $trade->{offer_description},
                $trade->{ask_description};
        }
        
        print "\n";
    }
}
