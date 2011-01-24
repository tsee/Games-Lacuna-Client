#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my $speed;
my $max;
my $from;
my $star;
my $planet;
my $trades_per_page = 25;

GetOptions(
    'speed=i'  => \$speed,
    'max=i'    => \$max,
    'from=s'   => \$from,
    'star=s'   => \$star,
    'planet=s' => \$planet,
);

usage() if !$from;

usage() if !$star && !$planet;

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
	 #debug    => 1,
);

my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};
my $target_id;
my $target_name;
my $target_type;

# Where are we sending to?

if ($star) {
    my $star_result = $client->map->get_star_by_name($star)->{star};
    
    if ($planet) {
        # send to planet on star
        my $bodies = $star_result->{bodies};
        
        my ($body) = first { $_->{name} eq $planet } @$bodies;
        
        die "Planet '$planet' not found at star '$star'"
            if !$body;
        
        $target_id   = $body->{id};
        $target_name = "$planet [$star]";
        $target_type = "body_id";
    }
    else {
        # send to star
        $target_id   = $star_result->{id};
        $target_name = $star;
        $target_type = "star_id";
    }
}
else {
    # send to own colony
    for my $key (keys %$planets) {
        if ( $planets->{$key} eq $planet ) {
            $target_id   = $key;
            $target_name = $planet;
            $target_type = "body_id";
            last;
        }
    }
    
    die "Colony '$planet' not found"
        if !$target_id;
}

# Where are we sending from?

my $from_id;

for my $key (keys %$planets) {
    if ( $planets->{$key} eq $from ) {
        $from_id = $key;
        last;
    }
}

die "From colony '$from' not found"
    if !$from_id;

# Load planet data
my $body      = $client->body( id => $from_id );
my $result    = $body->get_buildings;
my $buildings = $result->{buildings};

# Find the Subspace Transporter
my $transporter_id = first {
        $buildings->{$_}->{name} eq 'Subspace Transporter'
} keys %$buildings;

return if !$transporter_id;

my $transporter = $client->building( id => $transporter_id, type => 'Transporter' );

# Find waste trades
my @trades = get_trades();

# Find the first Space Port
my $space_port_id = first {
        $buildings->{$_}->{name} eq 'Space Port'
} keys %$buildings;

my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

my $ships = $space_port->get_ships_for( $from_id, { body_id => $target_id}  );

my $available = $ships->{available};
my $sent = 0;
my %trade_withdrawn;

@$available = grep { $_->{type} eq "scow" } @$available;

for my $ship ( @$available ) {
    next if $speed && $speed != $ship->{speed};
    
    my $trade =
        first {
               $_->{offer_quantity} == $ship->{hold_size}
            && !$trade_withdrawn{ $_->{id} }
        }
        @trades;
    
    next if !$trade;
    
    $space_port->send_ship( $ship->{id}, { $target_type => $target_id } );
    
    # withdraw trade
    $transporter->withdraw_trade( $trade->{id} );
    $trade_withdrawn{ $trade->{id} } = 1;
    
    printf "Sent %s to %s\n", $ship->{name}, $target_name;
    
    $sent++;
    last if $max && $max == $sent;
}


sub get_trades {
    my $trades = $transporter->view_my_trades;
    my $count  = $trades->{trade_count};
    
    return if !$count;
    
    my $page = 1;
    
    my @trades = @{ $trades->{trades} };
    
    $count -= $trades_per_page;
    
    while ( $count > 0 ) {
        $page++;
        
        push @trades, @{ $transporter->view_my_trades( $page )->{trades} };
        
        $count -= $trades_per_page;
    }
    
    @trades = grep { $_->{offer_type} eq 'waste' } @trades;
    
    return @trades;
}


sub usage {
  die <<"END_USAGE";
Usage: $0 send_scows.yml
       --speed      SPEED
       --max        MAX
       --from       NAME  (required)
       --star       NAME
       --planet     NAME

There must be at least as much waste already in storage as the largest
hold-size of any scow being sent, as get_ships_for() will only return scows
for which there is sufficient waste available.

Each scow is only sent if there is a SST trade available, whose waste offered
exactly matches the hold-size of the scow.
Each trade is withdrawn after each scow is sent, to avoid overflowing the
waste storage.

If --max is set, this is the maximum number of matching ships that will be
sent. Default behaviour is to send all matching ships.

--from is the colony from which the ship should be sent.

If --star is missing, the planet is assumed to be one of your own colonies.

At least one of --star or --planet is required.

END_USAGE

}
