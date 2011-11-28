#!/usr/bin/perl
#
# =================
#   Glyphinator
# =================
#
# Digs:
#   *) Collect list of current glyphs
#   *) On each ready planet, search in order of:
#       1. What we have the fewest glyphs of
#       2. What we have the most ore of
#       3. Random
#   *) Dig!
#
# Excavators:
#   *) Get list of ready excavators
#   *) Get closest ready body for each excavator
#   *) Launch!
#
# Spit out interesting times
#   *) When digs will be done
#   *) When excavators will arrive
#   *) When excavators will be finished building

use strict;
use warnings;

use feature ':5.10';

use DBI;
use FindBin;
use List::Util qw(first min max sum reduce);
use POSIX qw(ceil);
use Date::Parse qw(str2time);
use Math::Round qw(round);
use Getopt::Long;
use Data::Dumper;
use Exception::Class;

use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;

my @batches;
my $current_batch = 0;
my $batch_opt_cb = sub {
    my ($opt, $val) = @_;

    if ($opt eq 'and') {
        $current_batch++;
        return;
    }

    $batches[$current_batch]{$opt} = $val;
};
my %opts;
GetOptions(\%opts,
    # General options
    'h|help',
    'q|quiet',
    'v|verbose',
    'config=s',
    'planet=s@',
    'dry-run|dry',
    'full-times',

    # Arch digs
    'do-digs|dig',
    'min-ore=i',
    'min-arch=i',
    'preferred-ore|ore=s',

    # Excavator options
    'db=s',
    'send-excavators|send',
    'rebuild',
    'fill:i',
    'max-build=i',
    'save-spots=i',

    'and'                     => $batch_opt_cb,
    'max-excavators|max=s'    => $batch_opt_cb,
    'min-dist=i'              => $batch_opt_cb,
    'max-dist=i'              => $batch_opt_cb,
    'zone=s'                  => $batch_opt_cb,
    'safe-zone-ok'            => $batch_opt_cb,
    'inhabited-ok'            => $batch_opt_cb,
    'furthest-first|furthest' => $batch_opt_cb,
    'random-dist|random'      => $batch_opt_cb,

    # Allow this to run in an infinate glyph-sucking loop.  Value is
    # minutes between cycles (default 360)
    'continuous:i',
) or usage();
push @batches, {} unless @batches;

usage() if $opts{h};

# Consider probe data from within the last 3 days to be recent
# enough to believe inhabited status
my $RECENT_CHECK = 86400 * 3;

my %do_planets;
if ($opts{planet}) {
    %do_planets = map { normalize_planet($_) => 1 } @{$opts{planet}};
}

my $star_util = "$FindBin::Bin/star_db_util.pl";
no warnings 'once';
my $db_file = $opts{db} || "$FindBin::Bin/../stars.db";
my ($star_db, $have_last_checked);
if (-f $db_file) {
    $star_db = DBI->connect("dbi:SQLite:$db_file")
        or die "Can't open star database $db_file: $DBI::errstr\n";
    $star_db->{RaiseError} = 1;
    $star_db->{PrintError} = 0;
} else {
    warn "No star database found.  Specify it with --db or use $star_util --create-db to create it.\n";
    if ($opts{'send-excavators'}) {
        warn "Can't send excavators without star database!\n";
    }
}
if ($star_db) {
    # Check that db is populated
    my ($cnt) = $star_db->selectrow_array('select count(*) from orbitals');
    unless ($cnt) {
        diag("Star database is empty!\n");
        $star_db = undef;
    }
}
if ($star_db) {
    # Check if orbitals has last_checked
    my $ok = eval {
        $star_db->do('select last_checked from orbitals limit 1');
        return 1;
    };
    if ($ok) {
        $have_last_checked = 1;
    }

    # Check upgrade status
    $ok = eval {
        $star_db->do('select zone from stars limit 1');
        return 1;
    };
    unless ($ok) {
        my $e = $@;
        if ($e =~ /no such column/) {
            die "Database needs an upgrade, please run $star_util --upgrade\n";
        } else {
            die $e;
        }
    }
}

my ($finished, $status, $glc);
while (!$finished) {
    my $ok = eval {
        # We'll create this inside the loop for a couple reasons, primarily
        # that it gives us a chance to reauth each time through the loop, in
        # case you get the "Session expired" error.
        $glc = Games::Lacuna::Client->new(
            cfg_file       => $opts{config} || "$FindBin::Bin/../lacuna.yml",
            rpc_sleep      => 1.333, # 45 per minute, new default is 50 rpc/min
        );

        output("Starting up at " . localtime() . "\n");
        get_status();
        do_digs() if $opts{'do-digs'};
        send_excavators() if $opts{'send-excavators'} and $star_db;
        report_status();
        output(pluralize($glc->{total_calls}, "api call") . " made.\n");
        output("You have made " . pluralize($glc->{rpc_count}, "call") . " today\n");
        return 1;
    };
    unless ($ok) {
        my $e = $@;

        diag("Error during run: $@\n");

        if (my $e = Exception::Class->caught('LacunaRPCException')) {
            if ($e->code eq '1006' and $e->text =~ /Session expired/) {
                diag("Caught Session expired error, retrying\n");
                $status = {};
                redo;
            }
            $e->rethrow;
        } else {
            my $e = Exception::Class->caught();
            if ($e =~ /malformed JSON string/) {
                diag("Caught malformed JSON error, restarting\n");
                $status = {};
                redo;
            }
            ref $e ? $e->rethrow : die $e;
        }
    }

    if (defined $opts{continuous}) {
        my $sleep = $opts{continuous} || 360;

        if ($opts{'do-digs'} and $status->{digs}) {
            my $now = time();
            my ($last_dig) =
                map  { ceil(($_->{finished} - $now) / 60) }
                sort { $b->{finished} <=> $a->{finished} }
                @{$status->{digs}};

            if (defined $last_dig) {
                # Sleep until the digs end, but at least 10 minutes, unless asked to not wait that long
                $sleep = min($sleep, max($last_dig, 10));
            }
        }

        # Clear cache before sleeping
        $status = {};

        my $next = localtime(time() + ($sleep * 60));
        output("Sleeping for " . pluralize($sleep, "minute") . ", next run at $next\n");
        $sleep *= 60; # minutes to seconds
        sleep $sleep;
    } else {
        $finished = 1;
    }
}

# Destroy client object prior to global destruction to avoid GLC bug
undef $glc;

exit 0;

sub get_status {
    my $empire = $glc->empire->get_status->{empire};

    # reverse hash, to key by name instead of id
    my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
    $status->{planets} = \%planets;

    # Scan each planet
    my $now = time();
    for my $planet_name (keys %planets) {
        if (keys %do_planets) {
            next unless $do_planets{normalize_planet($planet_name)};
        }

        verbose("Inspecting $planet_name\n");

        # Load planet data
        my $planet    = $glc->body(id => $planets{$planet_name});
        my $result    = $planet->get_buildings;
        my $buildings = $result->{buildings};
        $status->{planet_location}{$planet_name}{x} = $result->{status}{body}{x};
        $status->{planet_location}{$planet_name}{y} = $result->{status}{body}{y};
        $status->{planet_resources}{$planet_name}{$_} = $result->{status}{body}{$_}
            for qw/water_hour energy_hour ore_hour food_hour/;

        my ($arch, $level, $seconds_remaining) = find_arch_min($buildings);
        if ($arch) {
            verbose("Found an archaeology ministry on $planet_name\n");
            $status->{archmin}{$planet_name}   = $arch;
            $status->{archlevel}{$planet_name} = $level;
            if ($seconds_remaining) {
                push @{$status->{digs}}, {
                    planet   => $planet_name,
                    finished => $now + $seconds_remaining,
                };
            } else {
                $status->{idle}{$planet_name} = 1;
                $status->{available_ore}{$planet_name} =
                    $arch->get_ores_available_for_processing->{ore};
            }

            my $glyphs = $arch->get_glyphs->{glyphs};
            for my $glyph (@$glyphs) {
                $status->{glyphs}{$glyph->{type}}++;
            }
        } else {
            verbose("No archaeology ministry on $planet_name\n");
        }

        my $spaceport = find_spaceport($buildings);
        if ($spaceport) {
            verbose("Found a spaceport on $planet_name\n");
            $status->{spaceports}{$planet_name} = $spaceport;

            # How many in flight?  When arrives?
            my $result = $spaceport->view_all_ships({no_paging => 1});
            my @ships = @{$result->{ships}};
            my @excavators = grep { $_->{type} eq 'excavator' } @ships;

            push @{$status->{flying}},
                map {
                    $_->{distance} = int(($_->{arrives} - $_->{departed}) * $_->{speed} / 360000);
                    $_->{remaining} = int(($_->{arrives} - $now) * $_->{speed} / 360000);
                    $_
                }
                map {
                    {
                        planet      => $planet_name,
                        destination => $_->{to}{name},
                        speed       => $_->{speed},
                        departed    => str2time(
                            map { s!^(\d+)\s+(\d+)\s+!$2/$1/!; $_ }
                            $_->{date_started}
                        ),
                        arrives     => str2time(
                            map { s!^(\d+)\s+(\d+)\s+!$2/$1/!; $_ }
                            $_->{date_arrives}
                        ),
                    }
                }
                grep { $_->{task} eq 'Travelling' }
                @excavators;

            # How many ready now?
            $status->{ready}{$planet_name} = [grep { $_->{task} eq 'Docked' } @excavators];
            verbose(pluralize(scalar @{$status->{ready}{$planet_name}}, "excavator") . " ready to launch\n");

            # How many open spots?
            my $total_docks = get_spaceport_dock_count($buildings);
            $status->{open_docks}{$planet_name} = $total_docks - @ships;
            verbose(pluralize($status->{open_docks}{$planet_name}, "available dock") . "\n");
        } else {
            verbose("No spaceport on $planet_name\n");
        }

        if ($status->{archlevel}{$planet_name} and $status->{archlevel}{$planet_name} >= 15) {
            my @shipyards = find_shipyards($buildings);
            verbose("No shipyards on $planet_name\n") unless @shipyards;
            for my $yard (@shipyards) {
                verbose("Found a shipyard on $planet_name\n");

                # Keep a record of any planet that could be building excavators, but isn't
                $status->{can_build}{$planet_name} = 1;
                $status->{not_building}{$planet_name} = 1
                    unless exists $status->{not_building}{$planet_name};

                # How many building?
                my $page = 1;
                my (@ships_building, $building_count);
                while (!defined $building_count or @ships_building < $building_count) {
                    my $work_queue = $yard->view_build_queue($page);
                    $building_count ||= $work_queue->{number_of_ships_building};
                    push @ships_building, @{$work_queue->{ships_building}};
                    $page++;
                }
                my @excavators_building =
                    map {
                        {
                            finished => str2time(
                                map { s!^(\d+)\s+(\d+)\s+!$2/$1/!; $_ }
                                $_->{date_completed}
                            ),
                        }
                    }
                    grep { $_->{type} eq 'excavator' }
                    @ships_building;

                my $last = $now;
                if (@excavators_building) {
                    verbose(pluralize(scalar @excavators_building, "excavator") . " building at this yard\n");
                    push @{$status->{building}{$planet_name}}, @excavators_building;
                    $status->{not_building}{$planet_name} = 0;
                    $last = max(map { $_->{finished} } @excavators_building);
                }

                push @{$status->{shipyards}{$planet_name}}, {
                    yard          => $yard,
                    last_finishes => $last,
                    build_time    => 0, # placeholder in case this doesn't get populated
                };
            }
        } else {
            verbose("$planet_name can't build excavators, skipping shipyards\n")
        }
    }
}

sub report_status {
    if (keys %{$status->{glyphs} || {}}) {
        my $total_glyphs = 0;
        output("Current glyphs:\n");
        my $cnt;
        for my $glyph (sort keys %{$status->{glyphs}}) {
            $total_glyphs += $status->{glyphs}->{$glyph};
            output(sprintf '%13s: %3s', $glyph, $status->{glyphs}->{$glyph});
            output("\n") unless ++$cnt % 4
        }
        output("\n") if $cnt % 4;
        output("\n");
        output("Current stock: " . pluralize($total_glyphs, "glyph") . "\n\n");
    }

    # Ready to go now?
    if (my @planets = grep { scalar @{$status->{ready}{$_}} } keys %{$status->{ready}}) {
        output(<<END);
**** Notice! ****
You have excavators ready to send.  Specify --send-excavators if you want to
send them to the closest available destinations.
*****************
END
        for my $planet (sort @planets) {
            output("$planet has ", pluralize(scalar @{$status->{ready}{$planet}}, 'excavator')
                , " ready to launch!\n");
        }
        output("\n");
    }

    # Any idle archmins?
    if (keys %{$status->{idle}}) {
        output(<<END);
**** Notice! ****
You have idle archaeology minstries.  Specify --do-digs if you want to
start the recommended digs automatically.
*****************
END
        for my $planet (keys %{$status->{idle}}) {
            output("Archaeology Ministry on $planet is idle!\n");
        }
        output("\n");
    }


    my $building_count = 0;
    my $yard_count = grep { $_->{last_finishes} } map { @$_ } values %{$status->{shipyards}};
    if (grep { @{$status->{building}{$_}} } keys %{$status->{building}}
        or grep { $status->{not_building}{$_} } keys %{$status->{not_building}}) {

        output("Excavators building:\n");
        for my $planet (sort keys %{$status->{planets}}) {
            if ($status->{building}{$planet} and @{$status->{building}{$planet}}) {
                $building_count += @{$status->{building}{$planet}};
                my @sorted = sort { $a->{finished} <=> $b->{finished} }
                    @{$status->{building}{$planet}};

                my $first = $sorted[0];
                my $last = $sorted[$#sorted];

                output("    ", pluralize(scalar(@sorted), "excavator"), " building on $planet, ",
                    "first done in ", format_time($first->{finished}, $opts{'full-times'}),
                    ", last done in ", format_time($last->{finished}, $opts{'full-times'}), "\n");

            } elsif ($status->{not_building}{$planet}) {
                output("$planet is not currently building any excavators!  It has "
                    . pluralize($status->{open_docks}{$planet}, 'spot') . " currently available.\n");
            }
        }
        output("\n");
    }

    my @events;
    my $digging_count = @{$status->{digs} || []};
    for my $dig (@{$status->{digs}}) {
        push @events, {
            epoch  => $dig->{finished},
            detail => "Dig finishing on $dig->{planet}",
        };
    }

    my $flying_count = @{$status->{flying} || []};
    for my $ship (@{$status->{flying} || []}) {
        push @events, {
            epoch  => $ship->{arrives},
            detail => "Excavator from $ship->{planet} arriving at $ship->{destination} (" . pluralize($ship->{distance}, "unit") . ", $ship->{remaining} left)",
        };
    }
    @events =
        sort { $a->{epoch} <=> $b->{epoch} }
        map  { $_->{when} = format_time($_->{epoch}, $opts{'full-times'}); $_ }
        @events;

    if (@events) {
        output("Searches completing:\n");
        for my $event (@events) {
            display_event($event);
        }
    }

    output("\n");
    output("Summary: " . pluralize($flying_count, "excavator") . " in flight, " . pluralize($yard_count, "shipyard") . " building " . pluralize($building_count, "excavator") . ", " . pluralize($digging_count, "dig") . " ongoing\n\n");
    for my $planet (keys %{$status->{build_limits}}) {
        output("$planet needs more $status->{build_limits}{$planet}{type}\n");
    }
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub format_time_delta {
    my ($delta, $strict) = @_;

    given ($delta) {
        when ($_ < 0) {
            return "just finished";
        }
        when ($_ < ($strict ? 60 : 90)) {
            return pluralize($_, 'second');
        }
        when ($_ < ($strict ? 3600 : 5400)) {
            my $min = round($_ / 60);
            return pluralize($min, 'minute');
        }
        when ($_ < 86400) {
            my $hrs = round($_ / 3600);
            return pluralize($hrs, 'hour');
        }
        default {
            my $days = round($_ / 86400);
            return pluralize($days, 'day');
        }
    }
}

sub format_time_delta_full {
    my ($delta) = @_;

    return "just finished" if $delta <= 0;

    my @formatted;
    my $sec = $delta % 60;
    if ($sec) {
        unshift @formatted, format_time_delta($sec,1);
        $delta -= $sec;
    }
    my $min = $delta % 3600;
    if ($min) {
        unshift @formatted, format_time_delta($min,1);
        $delta -= $min;
    }
    my $hrs = $delta % 86400;
    if ($hrs) {
        unshift @formatted, format_time_delta($hrs,1);
        $delta -= $hrs;
    }
    my $days = $delta;
    if ($days) {
        unshift @formatted, format_time_delta($days,1);
    }

    return join(', ', @formatted);
}

sub format_time {
    my ($time, $full) = @_;
    my $delta = $time - time();
    return $full ? format_time_delta_full($delta) : format_time_delta($delta);
}

sub pluralize {
    my ($num, $word) = @_;

    if ($num == 1) {
        return "$num $word";
    } else {
        return "$num ${word}s";
    }
}

sub display_event {
    my ($event) = @_;

    output(sprintf "    %11s: %s\n", $event->{when}, $event->{detail});
}

## Buildings ##

sub find_arch_min {
    my ($buildings) = @_;

    # Find the Archaeology Ministry
    my $arch_id = first {
            $buildings->{$_}->{name} eq 'Archaeology Ministry'
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not $arch_id;

    my $building  = $glc->building(
        id   => $arch_id,
        type => 'Archaeology',
    );
    my $level     = $buildings->{$arch_id}{level};
    my $remaining = $buildings->{$arch_id}{work} ? $buildings->{$arch_id}{work}{seconds_remaining} : undef;

    return ($building, $level, $remaining);
}

sub find_shipyards {
    my ($buildings) = @_;

    # Find the Shipyards
    my @yard_ids = grep {
            $buildings->{$_}->{name} eq 'Shipyard'
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not @yard_ids;
    return map { $glc->building(id => $_, type => 'Shipyard') } @yard_ids;
}

sub find_spaceport {
    my ($buildings) = @_;

    # Find a Spaceport
    my $port_id = first {
            $buildings->{$_}->{name} eq 'Space Port'
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not $port_id;
    return $glc->building(id => $port_id, type => 'Spaceport');
}

sub get_spaceport_dock_count {
    my ($buildings) = @_;

    my $level_sum = sum(
        map  { $buildings->{$_}->{level} }
        grep { $buildings->{$_}->{name} eq 'Space Port' }
        keys %$buildings
    );

    return $level_sum * 2;
}

## Arch digs ##

sub do_digs {

    # Try to avoid digging for the same ore on every planet, even if it's
    # determined somehow to be the "best" option.  We don't have access to
    # whatever digs are currently in progress so we'll base this just on what
    # we've started during this run.  This will be computed simply by adding
    # each current dig to glyphs, as if it were going to be successful.
    my $digging = {};

    for my $planet (keys %{$status->{idle}}) {
        if ($opts{'min-arch'} and $status->{archlevel}{$planet} < $opts{'min-arch'}) {
            output("$planet is not above specified Archaeology Ministry level ($opts{'min-arch'}), skipping dig.\n");
            next;
        }
        my $ore = determine_ore(
            $opts{'min-ore'} || 10_000,
            $opts{'preferred-ore'} || [],
            $status->{available_ore}{$planet},
            $status->{glyphs},
            $digging
        );
        if ($ore) {
            if ($opts{'dry-run'}) {
                output("Would have started a dig for $ore on $planet.\n");
            } else {
                output("Starting a dig for $ore on $planet...\n");
                my $ok = eval {
                    $status->{archmin}{$planet}->search_for_glyph($ore);
                    push @{$status->{digs}}, {
                        planet   => $planet,
                        finished => time() + (6 * 60 * 60),
                    };
                    return 1;
                };
                unless ($ok) {
                    my $e = $@;
                    diag("Error starting dig: $e\n");
                }
            }
            delete $status->{idle}{$planet};
        } else {
            output("Not starting a dig on $planet; not enough of any type of ore.\n");
        }
    }
}

sub determine_ore {
    my ($min, $preferred, $ore, $glyphs, $digging) = @_;

    my %is_preferred = map { $_ => 1 } @$preferred;

    my ($which) =
        sort {
            ($is_preferred{$b} || 0) <=> ($is_preferred{$a} || 0) or
            ($glyphs->{$a} || 0) + ($digging->{$a} || 0) <=> ($glyphs->{$b} || 0) + ($digging->{$b} || 0) or
            $ore->{$b} <=> $ore->{$a} or
            int(rand(3)) - 1
        }
        grep { $ore->{$_} >= $min }
        keys %$ore;

    if ($which) {
        $digging->{$which}++;
    }

    return $which;
}


## Excavators ##

sub send_excavators {
    PLANET:

    # This skips ones that have no {ready} but could build!
    for my $planet (keys %{$status->{planets}}) {

        my $launch_count;
        my $built_count = 0;
        if ($status->{ready}{$planet} and @{$status->{ready}{$planet}}) {
            verbose("Prepping excavators on $planet\n");
            my $port = $status->{spaceports}{$planet};
            my $originally_docked = @{$status->{ready}{$planet}};
            my $warned_cant_verify;

            # During a dry-run, not actually updating the database results in
            # each excavator from each planet going to the same target.  Add
            # them to an exclude list to simulate them being actually used.
            my %skip;

            BATCH:
            for my $batch (@batches) {
                my $docked = @{$status->{ready}{$planet}};

                if ($docked == 0) {
                    diag("Ran out of excavators before batches were complete!\n");
                    delete $status->{ready}{$planet};
                    last BATCH;
                }

                my $count = $batch->{'max-excavators'} // $docked;
                if ($count =~ /^(\d+)%/) {
                    $count = max(int(($1 / 100) * $originally_docked), 1);
                }
                $count = min($count, $docked);

                my @dests = pick_destination(
                    planet => $planet,
                    count  => $count,
                    batch  => $batch,
                );

                if (@dests < $count) {
                    diag("Couldn't fetch " . pluralize($count, "destination") . " from $planet!\n");
                }

                my $all_done;
                while (!$all_done) {
                    my $need_more = 0;

                    for (@dests) {
                        my ($dest_name, $x, $y, $distance, $zone, $checked_epoch) = @$_;

                        # Get the next available excavator
                        my $ex = $status->{ready}{$planet}[0];

                        unless (defined $ex) {
                            diag("No excavators left when we still had destinations, possible bug?\n");
                            $all_done = 1;
                            last;
                        }

                        # Only try each destination once
                        $skip{$dest_name}++;

                        if ($opts{'dry-run'}) {
                            output("Would have sent excavator from $planet to $dest_name (" . pluralize($distance, "unit") . ", zone $zone).\n");
                        } else {
                            output("Sending excavator from $planet to $dest_name (" . pluralize($distance, "unit") . ", zone $zone)...\n");
                            my $launch_status;
                            my $ok = eval {
                                $launch_status = $port->send_ship($ex->{id}, {x => $x, y => $y});
                                return 1;
                            };
                            unless ($ok) {
                                if (my $e = Exception::Class->caught('LacunaRPCException')) {
                                    if ($e->code eq '1002') {
                                        # Empty orbit, update db and try again
                                        output("$dest_name is an empty orbit, trying again...\n");
                                        mark_orbit_empty($x, $y);

                                        $need_more++;
                                        next;
                                    }

                                    if ($e->code eq '1010') {
                                        # This will set the "last_excavated" time to now, which is not
                                        # the case, but it's as good as we have.  It means that some bodies
                                        # might take longer to get re-dug but whatever, there are others
                                        output("$dest_name was unavailable due to recent search, trying again...\n");
                                        update_last_sent($x, $y);

                                        $need_more++;
                                        next;
                                    }

                                    if ($e->code eq '1016' and !$batch->{'inhabited-ok'}) {
                                        output("$dest_name would have triggered defenses, trying again...\n");
                                        mark_orbit_occupied($x, $y);
                                        $need_more++;
                                        next;
                                    }
                                }
                                else {
                                    my $e = Exception::Class->caught();
                                    diag("Unknown error sending excavator from $planet to $dest_name: $e\n");
                                }
                            }

                            if ($launch_status->{ship}->{date_arrives}) {
                                $launch_count++;
                                push @{$status->{flying}},
                                    {
                                        planet      => $planet,
                                        destination => $launch_status->{ship}{to}{name},
                                        speed       => $ex->{speed},
                                        distance    => $distance,
                                        remaining   => $distance,
                                        departed    => time(),
                                        arrives     => str2time(
                                            map { s!^(\d+)\s+(\d+)\s+!$2/$1/!; $_ }
                                            $launch_status->{ship}{date_arrives}
                                        ),
                                    };

                                    update_last_sent($x, $y);
                            } else {
                                diag("Error sending excavator to $dest_name!\n");
                                warn Dumper $launch_status;
                            }
                        }

                        shift @{$status->{ready}{$planet}};
                    }

                    # Defer looking up more until we've finished processing our
                    # current queue, otherwise we end up re-fetching ones we haven't
                    # actually tried yet and get duplicates
                    if ($need_more) {
                        @dests = pick_destination(
                            planet => $planet,
                            count  => $need_more,
                            batch  => $batch,
                            skip   => [keys %skip],
                        );
                    } else {
                        $all_done = 1;
                    }
                }
            }

            delete $status->{ready}{$planet}
                if !$status->{ready}{$planet} or !@{$status->{ready}{$planet}};

        }

        if ($status->{can_build}{$planet}) {
            my $build = 0;
            if ($launch_count and $opts{rebuild}) {
                $build = $launch_count;
            }
            if (defined $opts{fill}) {
                # Compute how many we would need to build

                my $need = 0;
                my $minutes = $opts{fill} || $opts{continuous} || 360;
                my ($ore_cost, $energy_cost, $water_cost, $food_cost);
                for my $yard (@{$status->{shipyards}{$planet} || []}) {

                    # Get the length of a build here
                    my $buildable = $yard->{yard}->get_buildable;
                    my ($build_time) = map { $buildable->{buildable}{$_}{cost}{seconds} }
                        grep { $_ eq 'excavator' }
                        keys %{$buildable->{buildable}};
                    verbose("An excavator will take $build_time seconds in this yard\n");
                    $yard->{build_time} = $build_time;

                    # Figure out how much time we'd need to fill in for
                    my $finishes = $yard->{last_finishes} || time();
                    my $target_finish = time() + ($minutes * 60);
                    my $delta = $target_finish - $finishes;
                    verbose("$delta seconds of build needed to fill up shipyard to $minutes minutes\n");

                    my $new = 0;
                    if ($delta > 0) {
                        $new = int($delta / $build_time) + ($delta % $build_time ? 1 : 0);
                        verbose("Need " . pluralize($new, "additional excavator") . " based on build time\n");
                    }

                    $need += $new;

                    # Get the cost of a build
                    unless ($ore_cost) {
                        ($ore_cost, $energy_cost, $water_cost, $food_cost) =
                            map { @{$buildable->{buildable}{$_}{cost}}{qw/ore energy water food/} }
                            grep { $_ eq 'excavator' }
                            keys %{$buildable->{buildable}};
                    }
                }

                verbose("Would need " . pluralize($need, "ship") . " to fill up to $minutes minutes on $planet\n");
                $status->{build_limits}{$planet}{type} = 'Shipyard capacity';
                $status->{build_limits}{$planet}{num}  = $need;

                verbose("An excavator costs $ore_cost ore, $energy_cost energy, $water_cost water, and $food_cost food in this yard\n");
                my $by_ore    = $status->{planet_resources}{$planet}{ore_hour}    / $ore_cost;
                my $by_water  = $status->{planet_resources}{$planet}{water_hour}  / $water_cost;
                my $by_food   = $status->{planet_resources}{$planet}{food_hour}   / $food_cost;
                my $by_energy = $status->{planet_resources}{$planet}{energy_hour} / $energy_cost;
                my $by_resource = min($by_ore, $by_water, $by_food, $by_energy);
                my $need_by_resource = int($by_resource * ($minutes / 60));
                verbose("$planet can sustain $by_resource excavators per hour based on current production, for $need_by_resource in $minutes minutes\n");
                $need = min($need, $need_by_resource);
                if ($need < $status->{build_limits}{$planet}{num}) {
                    $status->{build_limits}{$planet}{num}  = $need;
                    my $type = $by_resource == $by_ore ? 'ore' : $by_resource == $by_water ? 'water' : $by_resource == $by_food ? 'food' : 'energy';
                    $status->{build_limits}{$planet}{type} = "$type production";
                }

                # make whichever is higher, the number calculated here, or from --rebuild
                $build = max($build, $need);
            }

            $build = min($build - $built_count, $opts{'max-build'} - $built_count)
                if defined $opts{'max-build'};

            verbose("Saving $opts{'save-spots'} spaceport spots\n") if $opts{'save-spots'};

            # reduce $build to at most the number of open spaceport slots, holding some open if requested
            verbose("Reducing to lesser of $build (need) and @{[$status->{open_docks}{$planet} - ($opts{'save-spots'} || 0)]} (spots)\n");
            $build = min($build, $status->{open_docks}{$planet} - ($opts{'save-spots'} || 0));
            if ($build < $status->{build_limits}{$planet}{num}) {
                $status->{build_limits}{$planet}{type} = 'Spaceport slots';
                $status->{build_limits}{$planet}{num}  = $build;
            }

            if ($build) {
                for (1..$build) {
                    # Add an excavator to a shipyard if we can, to wherever the
                    # shortest build queue is
                    my $yard = reduce { $a->{last_finishes} + $a->{build_time}
                        < $b->{last_finishes} + $b->{build_time} ? $a : $b }
                        @{$status->{shipyards}{$planet} || []};

                    # Catch if this dies, we didnt actually confirm that we could build
                    # an excavator in this yard at this time.  Queue could be full, or
                    # we could be out of materials, etc.  This is probably cheaper than
                    # doing the get_buildable call before every single build.
                    my $ok = eval {
                        if ($opts{'dry-run'}) {
                            output("Would have built an excavator on $planet\n");
                        } else {
                            output("Building an excavator on $planet\n");

                            my $build = $yard->{yard}->build_ship('excavator');
                            my $finish = time() + $build->{building}{work}{seconds_remaining};

                            push @{$status->{building}{$planet}}, {
                                finished => $finish,
                            };
                            $yard->{last_finishes} = $finish;
                            $status->{not_building}{$planet} = 0;
                        }
                        $built_count++;
                        return 1;
                    };
                    unless ($ok) {
                        # Assume that build errors mean that we're out of spaceport
                        # or shipyard slots, or resources, or something else non-recoverable
                        my $e = $@;
                        diag("Error rebuilding: $e\n");
                        last;
                    }
                }
            }
        }
    }
}

sub pick_destination {
    my (%args) = @_;

    my $planet = $args{planet};
    my $batch  = $args{batch};
    my $base_x = $status->{planet_location}{$planet}{x};
    my $base_y = $status->{planet_location}{$planet}{y};

    # Compute box size based on specified max hypotenuse
    my $min_dist = $batch->{'min-dist'} || 0;
    my $max_dist = $batch->{'max-dist'} || 3000;
    my $box_min = $min_dist ? int(sqrt($min_dist * $min_dist / 2)) : 0;
    my $box_max = int(sqrt($max_dist * $max_dist / 2));
    my $max_squared = $max_dist * $max_dist;
    my $min_squared = $min_dist * $min_dist;

    my $count       = $args{count} // 1;
    my $current_min = $box_max;
    my $current_max = $box_min;
    my $skip        = $args{skip} || [];

    my $furthest = $batch->{'furthest-first'};

    verbose("Seeking " . pluralize($count, "destination") . " for $planet\n");

    my @results;
    while (@results < $count and ($furthest ? $current_min > 0 : $current_max < $box_max)) {
        if ($batch->{'random-dist'}) {
            # Use full range for random searches
            $current_min = $box_min;
            $current_max = $box_max;
            verbose("Setting to full range for random search\n");
        }
        elsif ($furthest) {
            $current_max = $current_min;
            $current_min -= 100;
            $current_min = 0 if $current_min < 0;
            verbose("Decreasing box size, max is $current_max, min is $current_min\n");
        } else {
            $current_min = $current_max;
            $current_max += 100;
            $current_max = $box_max if $current_max > $box_max;
            verbose("Increasing box size, max is $current_max, min is $current_min\n");
        }

        # This would be better using SQLite's R*Tree support, but DBD::SQLite doesn't
        # support that yet, so we can't
        my $skip_sql = '';
        if (@$skip) {
            $skip_sql = "and s.name || ' ' || o.orbit not in (" . join(',',map { '?' } 1..@$skip) . ")";
        }
        my $last_checked = $have_last_checked ? q{, strftime('%s', o.last_checked) as checked_epoch} : '';
        my $inner_box    = $current_min > 0 ? 'and not (o.x between ? and ? and o.y between ? and ?)' : '';
        my $safe_zone    = $batch->{'safe-zone-ok'} ? '' : q{and (s.zone is null or s.zone != '-3|0')};
        my $inhabited    = $batch->{'inhabited-ok'} ? '' : q{and o.empire_id is null};
        my $zone         = $batch->{'zone'} ? 'and zone = ?' : '';
        my $order        = $batch->{'furthest-first'} ? 'desc' : 'asc';
        my $rand         = $batch->{'random-dist'} ? "+ random()" : '';
        my $find_dest    = $star_db->prepare(<<SQL);
select   o.*, s.name as star_name, s.zone, (o.x - ?) * (o.x - ?) + (o.y - ?) * (o.y - ?) as dist,
         (((o.x - ?) * (o.x - ?) + (o.y - ?) * (o.y - ?)) $rand) as sort_dist
         $last_checked
from     orbitals o
join     stars s on o.star_id = s.id
where    (type in ('habitable planet', 'asteroid', 'gas giant') or type is null)
and      (last_excavated is null or date(last_excavated) < date('now', '-30 days'))
and      o.x between ? and ?
and      o.y between ? and ?
and      dist <= $max_squared
and      dist >= $min_squared
$skip_sql
$safe_zone
$inhabited
$zone
$inner_box
order by sort_dist $order
limit    $count
SQL

        # select columns,x/y betweens
        my @vals = (
            $base_x, $base_x, $base_y, $base_y,
            $base_x, $base_x, $base_y, $base_y,
            $base_x - $current_max,
            $base_x + $current_max,
            $base_y - $current_max,
            $base_y + $current_max,
            @$skip,
        );
        if ($batch->{zone}) {
            push @vals, $batch->{zone};
        }
        if ($current_min > 0) {
            push @vals,
                $base_x - $current_min,
                $base_x + $current_min,
                $base_y - $current_min,
                $base_y + $current_min,
        }

        $find_dest->execute(@vals);
        while (my $row = $find_dest->fetchrow_hashref) {
            my $dest_name = "$row->{star_name} $row->{orbit}";
            my $dist = int(sqrt($row->{dist}));
            verbose("Selected destination $dest_name, which is " . pluralize($dist, "unit") . " away\n");

            my $zone = $row->{zone};
            unless ($zone) {
                my $x_zone = int($row->{x} / 250);
                my $y_zone = int($row->{y} / 250);
                $zone = "$x_zone|$y_zone";
            }
            push @results, [$dest_name, $row->{x}, $row->{y}, $dist, $zone, $row->{checked_epoch} || 0];
            push @$skip, $dest_name;
        }
    }

    return @results;
}

sub update_last_sent {
    my ($x, $y) = @_;

    my $r = $star_db->do(q{update orbitals set last_excavated = datetime(?,'unixepoch') where x = ? and y = ?}, {}, time(), $x, $y);
    unless ($r > 0) {
        diag("Warning: could not update orbitals table for body at $x, $y!\n");
    }
}

sub mark_orbit_empty {
    my ($x, $y) = @_;

    my $r = $star_db->do(q{update orbitals set type = 'empty' where x = ? and y = ?}, {}, $x, $y);
    unless ($r > 0) {
        diag("Warning: could not update orbitals table for body at $x, $y!\n");
    }
}

sub mark_orbit_occupied {
    my ($x, $y) = @_;

    my $r = $star_db->do(q{update orbitals set empire_id = -1 where x = ? and y = ?}, {}, $x, $y);
    unless ($r > 0) {
        diag("Warning: could not update orbitals table for body at $x, $y!\n");
    }
}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program will manage your glyph hunting worries with minimal manual
intervention required.  It will notice archeology digs, ready-to-launch
excavators, and idle shipyards and notify you of them.  It can start digs
for the most needed glyphs, and send excavators to the nearest available
bodies.

This is suitable for automation with cron(8) or at(1), but you should
know that it tends to use a substantial number of API calls, often 50-100
per run.  With the daily limit of 5000, including all web UI usage, you
will want to keep these at a relatively infrequent interval, such as every
60 minutes at most.

Options:
  --verbose              - Output extra information.
  --quiet                - Print no output except for errors.
  --config <file>        - Specify a GLC config file, normally lacuna.yml.
  --db <file>            - Specify a star database, normally stars.db.
  --planet <name>        - Specify a planet to process.  This option can be
                           passed multiple times to indicate several planets.
                           If this is not specified, all relevant colonies will
                           be inspected.
  --continuous [<min>]   - Run the program in a continuous loop until interrupted.
                           If an argument is supplied, it should be the number of
                           minutes to sleep between runs.  If unspecified, the
                           default is 360 (6 hours).  If all arch digs will finish
                           before the next scheduled loop and --do-digs is specified,
                           it will instead run at that time.
  --do-digs              - Begin archaeology digs on any planets which are idle.
  --min-ore <amount>     - Do not begin digs with less ore in reserve than this
                           amount.  The default is 10,000.
  --min-arch <level>     - Do not begin digs on any archaeology ministry less
                           than this level.  The default is 1.
  --preferred-ore <type> - Dig using the specified ore whenever available.
  --send-excavators      - Launch ready excavators at their nearest destination.
                           The information for these is selected from the star
                           database, and the database is updated to reflect your
                           new searches.
  --rebuild              - Build a new excavator for each one sent
  --fill [<minutes>]     - Fill all shipyards with the minimum number of excavators
                           that will take at least <minutes> (default 360) to
                           complete.  If --continuous is specified, it will use that
                           value if not overridden here before defaulting to 360.
  --max-build <n>        - Build at most <n> excavators on each colony, after the
                           --rebuild and/or --fill rules are computed.
  --save-spots <n>       - Leave at least <n> Spaceport spots unfilled
  --max-excavators <n>   - Send at most this number of excavators from any colony.
                           This argument can also be specified as a percentage,
                           eg '25%'
  --min-dist <n>         - Minimum distance to send excavators
  --max-dist <n>         - Maximum distance to send excavators
  --zone <id>            - Specify a particular zone to send to, if possible
  --safe-zone-ok         - Ok to send excavators to -3|0, the neutral zone
  --inhabited-ok         - Ok to send excavators to inhabited planets
  --furthest-first       - Select the furthest away rather than the closest
  --random-dist          - Select random distances within the specified range
                           instead of the closest or furthest.
  --dry-run              - Don't actually take any action, just report status and
                           what actions would have taken place.
  --full-times           - Specify timestamps in full precision instead of rounded

The excavator arguments can be combined into separate batches, to allow you to
send with multiple set of criteria, separated by an --and argument.  All of the
options above starting with --max-excavators through --furthest-first may be
used independently in each batch.  An example might be:

    --max-excavators 2 --min-dist 500 --and --max-excavators '50%'

Which would first send 2 500 or more units, then half of the remaining docked
ones to their nearest destination.  This is repeated for each colony, or the ones
indicated by --planet
END
    exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
