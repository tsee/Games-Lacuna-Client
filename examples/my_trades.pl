#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw( first max );
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

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

my $trades_per_page = 25;

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

my %my_trades;

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if defined $planet_name && $planet_name ne $name;

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
        my $trade_min = $client->building( id => $trade_id, type => 'Trade' );

        my $trades = get_trades( $trade_min );

        if ( @$trades ) {
            $my_trades{$name}{'Trade Ministry'} = $trades;
        }
    }

    if ($transporter_id) {
        my $transporter = $client->building( id => $transporter_id, type => 'Transporter' );

        my $trades = get_trades( $transporter );

        if ( @$trades ) {
            $my_trades{$name}{'Subspace Transporter'} = $trades;
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

        for my $trade (@trades) {
            printf "Posted: %s\n", $trade->{date_offered};
            printf "\tAsking %d Essentia for:\n", $trade->{ask};

            for my $item ( @{ $trade->{offer} } ) {
                printf "\t%s\n", $item;
            }
        }

        print "\n";
    }
}

sub get_trades {
    my ( $building ) = @_;

    my $trades = $building->view_my_market;
    my $count  = $trades->{trade_count};

    return [] if !$count;

    my $page = 1;

    my @trades = @{ $trades->{trades} };

    $count -= $trades_per_page;

    while ( $count > 0 ) {
        $page++;

        push @trades, @{ $building->view_my_market( $page )->{trades} };

        $count -= $trades_per_page;
    }

    return \@trades;
}
