#!/usr/bin/perl

use strict;
use warnings;
use DateTime;
use Getopt::Long          (qw(GetOptions));
use List::Util            (qw(first));
use POSIX                  qw( floor );
use Time::HiRes            qw( sleep );
use Try::Tiny;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my $login_attempts  = 5;
my $reattempt_wait  = 0.1;

my @ship_names;
my @ship_types;
my $speed;
my $max;
my $leave = 0;
my $from;
my $share = 1;
my $x;
my $y;
my $star;
my $own_star;
my $planet;
my $fleet = 1;
my $fleet_speed = 0;
my $sleep;
my $seconds;
my $rename;
my $dryrun;
my $count = undef;

GetOptions(
    'ship=s@'           => \@ship_names,
    'type=s@'           => \@ship_types,
    'speed=i'           => \$speed,
    'max=i'             => \$max,
    'leave=i'           => \$leave,
    'from=s'            => \$from,
    'share=s'           => \$share,
    'x=i'               => \$x,
    'y=i'               => \$y,
    'star=s'            => \$star,
    'planet=s'          => \$planet,
    'fleet!'            => \$fleet,
    'fleet-speed=i'     => \$fleet_speed,
    'own-star|own_star' => \$own_star,
    'sleep=i'           => \$sleep,
    'seconds=i'         => \$seconds,
    'rename'            => \$rename,
    'count=i'           => \$count,
    'dryrun|dry-run'    => \$dryrun,
);

usage() if !@ship_names && !@ship_types;

usage() if !$from;

usage() if !$star && !$planet && !$own_star && !defined $x && !defined $y;

usage() if defined $x && !defined $y;
usage() if defined $y && !defined $x;

usage() if $own_star && $planet;

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
	cfg_file       => $cfg_file,
    prompt_captcha => 1,
	 #debug    => 1,
);

my $empire = request(
    object => $client->empire,
    method => 'get_status',
)->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

die "--from colony '$from' not found"
    if !$planets{$from};

my $target;
my $target_name;

# Where are we sending to?

if ( defined $x && defined $y ) {
    $target      = { x => $x, y => $y };
    $target_name = "$x,$y";
}
elsif ( defined $star ) {
    $target      = { star_name => $star };
    $target_name = $star;
}
elsif ( defined $planet ) {
    $target      = { body_name => $planet };
    $target_name = $planet;
}
elsif ( $own_star ) {
    my $body = $client->body( id => $planets{$from} );

    $body = request(
        object => $body,
        method => 'get_status',
    )->{body};

    $target      = { star_id => $body->{star_id} };
    $target_name = "own star";
}
else {
    die "target arguments missing\n";
}

# Load planet data
my $body = $client->body( id => $planets{$from} );

my $buildings = request(
    object => $body,
    method => 'get_buildings',
)->{buildings};

# Find the first Space Port
my $space_port_id = first {
        $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;

my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

my $get_ships_for = request(
    object => $space_port,
    method => 'get_ships_for',
    params => [
        $planets{$from},
        $target,
    ],
);

my $ships           = $get_ships_for->{available};
my $ships_per_fleet = $get_ships_for->{fleet_send_limit};

my @ships;

for my $ship ( @$ships ) {
    next if @ship_names && !grep { $ship->{name} eq $_ } @ship_names;
    next if @ship_types && !grep { $ship->{type} eq $_ } @ship_types;

    push @ships, $ship;
    last if defined $count && scalar @ships == $count;
}

# if --leave is used, try to leave as many as possible of the *wrong*
# speed, so we have more to send

if ( $speed ) {
    my @wrong_speed;
    my @right_speed;

    for my $ship ( @ships ) {
        if ( $ship->{speed} == $speed ) {
            push @right_speed, $ship;
        }
        else {
            push @wrong_speed, $ship;
        }
    }

    if ( @wrong_speed >= $leave ) {
        # we can use all the correct speed ships
        @ships = @right_speed;
    }
    else {
        my $diff = $leave - @wrong_speed;

        die "No ships available to send\n"
            if $diff > @right_speed;

        my $can_use = @right_speed - $diff;

        splice @right_speed, $can_use;

        @ships = @right_speed;
    }
}

if ( $max && $max < @ships ) {
    splice @ships, $max;
}

# honour --share
my $use_count = floor( $share * scalar @ships );

die "No ships available to send\n"
    if !$use_count;

splice @ships, $use_count;

# check fleet-speed is valid
if ( $fleet && $fleet_speed ) {
    my $slowShip = first {
        $_->{speed} < $fleet_speed
    } @ships;

    die "--fleet-speed: '$fleet_speed' exceeds slowest ship ($slowShip->{type} - $slowShip->{speed}) selected to send\n"
        if $slowShip;
}

# send immediately?

if ($seconds) {
    my $now_seconds = DateTime->now->second;

    if ( $now_seconds > $seconds ) {
        sleep $seconds - $now_seconds;
    }
}
elsif ($sleep) {
    print "Sleeping for $sleep seconds...\n";
    sleep $sleep;
}

if ( $dryrun ) {
    print "DRYRUN\n";
    print "======\n";

    print "Sent to: $target_name\n";

    for my $ship (@ships) {
        printf "%s\n", $ship->{name};
    }

    exit;
}

# don't send 1 ship as a fleet
if ( $fleet && !$fleet_speed && @ships == 1 ) {
    undef $fleet;
}

my @fleet;

for my $ship (@ships) {
    if ( $fleet ) {
        push @fleet, $ship;

        if ( @fleet == $ships_per_fleet ) {
            send_fleet( \@fleet );
            undef @fleet;
        }
    }
    else {
        send_ship( $ship );
    }
}

if ( @fleet ) {
    send_fleet( \@fleet );
}

if ( $rename ) {
    print "\n";

    # renaming isn't time-sensitive, so try to avoid hitting the max
    # requests per minute
    $client->rpc_sleep(1);

    for my $ship (@ships) {

        my $name = sprintf "%s (%s)",
            $ship->{type_human},
            $target_name;

        request(
            object => $space_port,
            method => 'name_ship',
            params => [
                $ship->{id},
                $name,
            ],
        );

        printf qq{Renamed "%s" to "%s"\n},
            $ship->{name},
            $name;
    }
}

exit;

sub send_ship {
    my ( $ship ) = @_;

    my $return = request(
        object => $space_port,
        method => 'send_ship',
        params => [
            $ship->{id},
            $target,
        ],
    );

    print "Sent ship to: $target_name\n";

    printf qq{\t%s "%s" arriving %s\n},
        $return->{ship}{type_human},
        $return->{ship}{name},
        $return->{ship}{date_arrives};
}

sub send_fleet {
    my ( $ships ) = @_;

    my $return = request(
        object => $space_port,
        method => 'send_fleet',
        params => [
            [ map { $_->{id} } @$ships ],
            $target,
            $fleet_speed,
        ],
    );

    print "Sent fleet to: $target_name\n";

    for my $ship ( @{ $return->{fleet} } ) {
        printf qq{\t%s "%s" arriving %s\n},
            $ship->{ship}{type_human},
            $ship->{ship}{name},
            $ship->{ship}{date_arrives};
    }
}

sub request {
    my ( %params )= @_;

    my $method = delete $params{method};
    my $object = delete $params{object};
    my $params = delete $params{params} || [];

    my $request;
    my $error;

RPC_ATTEMPT:
    for ( 1 .. $login_attempts ) {

        try {
            $request = $object->$method(@$params);
        }
        catch {
            $error = $_;

            # if session expired, try again without a session
            my $client = $object->client;

            if ( $client->{session_id} && $error =~ /Session expired/i ) {

                warn "GLC session expired, trying again without session\n";

                delete $client->{session_id};

                sleep $reattempt_wait;
            }
            else {
                # RPC error we can't handle
                # supress "exiting subroutine with 'last'" warning
                no warnings;
                last RPC_ATTEMPT;
            }
        };

        last RPC_ATTEMPT
            if $request;
    }

    if (!$request) {
        warn "RPC request failed $login_attempts times, giving up\n";
        die $error;
    }

    return $request;
}

sub usage {
  die <<"END_USAGE";
Usage: $0 lacuna.yml
       --ship        NAME
       --type        TYPE
       --speed       SPEED
       --max         MAX
       --leave       COUNT
       --share       PROPORTION OF AVAILABLE SHIPS TO SEND
       --from        NAME  (required)
       --x           COORDINATE
       --y           COORDINATE
       --star        NAME
       --planet      NAME
       --own-star
       --fleet
       --fleet-speed SPEED
       --sleep       SECONDS
       --seconds     SECONDS
       --rename
       --dryrun

Either of --ship_name or --type is required.

--ship_name can be passed multiple times.

--type can be passed multiple times.
It must match the ship's "type", not "type_human", e.g. "scanner", "spy_pod".

If --max is set, this is the maximum number of matching ships that will be
sent. Default behaviour is to send all matching ships.

If --leave is set, this number of ships will be kept on the planet. This counts
all ships of the desired type, regardless of any --speed setting.

--share is the proportion of available ships to send (after taking into account
--max and --leave). Defaults to 1, meaning all ships. 0.5 would mean 50% of
ships.

--from is the colony from which the ship should be sent.

If --star is missing, the planet is assumed to be one of your own colonies.

At least one of --star or --planet or --own-star or both --x and --y are
required.

--own-star and --planet cannot be used together.

If --fleet is true, will send up to 20 ships in a fleet at once.
Fleet defaults to true.
--nofleet will force sending all ships individually.
If only 1 ship is being sent and --fleet-speed is not set, it will not be sent
as a fleet.

If --fleet-speed is set, all ships will travel at that speed.
It is a fatal error to specify a speed greater than the slowest ship being sent.

If --seconds is specified, what until that second of the current minute before
sending. If that second has already passed, send immediately.

If --sleep is specified, will wait that number of seconds before sending ships.
Ignored if --seconds is set.

If --rename is provided, each ship sent will be renamed using the form
"Type (Target)". This may be helpful for keeping track of fighters on remote
defense.

If --dryrun is provided, nothing will be sent, but all actions that WOULD
happen are reported

END_USAGE

}
