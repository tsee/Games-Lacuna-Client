package Games::Lacuna::Client::Governor;
use strict;
use warnings;
no warnings 'uninitialized'; # Yes, I count on undef to be zero.  Cue admonishments.

use Games::Lacuna::Client::PrettyPrint qw(trace message warning action ptime phours);
use List::Util qw(sum max min);
use List::MoreUtils qw(any part);
use Hash::Merge qw(merge);
use JSON qw(to_json from_json);

use Data::Dumper;

sub new {
    my ($self, $client, $config_opt) = @_;

    my $config;
    if (not ref $config_opt) {
        open my $fh, '<', $config_opt or die "Couldn't open $config_opt";
        $config = YAML::Any::Load( do { local $/; <$fh> } );
        close $fh;
    }
    else {
        $config = $config_opt;  # We passed in a literal hashref for config. Right?
    }

    return bless {
        client => $client,
        config => $config,
    },$self;
}

sub run {
    my $self = shift;
    my $client = $self->{client};
    my $config = $self->{config};

    my $data = $client->empire->view_species_stats();
    $self->{status} = $data->{status};
    my $planets        = $self->{status}->{empire}->{planets};
    my $home_planet_id = $self->{status}->{empire}->{home_planet_id};
    $self->{planet_names} = { map { $_ => $planets->{$_} } keys %$planets };

    my $do_keepalive = 1;
    my $start_time = time();

    $self->load_building_cache();

    do {
        if ( $self->{config}->{dry_run} ) {
            message("Starting dry run, actions are not actually taking place...");
        }
        $do_keepalive = 0;
        for my $pid ( keys %$planets ) {
            next if ( time() < $self->{next_action}->{$pid} );
            trace( "Examining " . $planets->{$pid} ) if ( $self->{config}->{verbosity}->{trace} );
            my $colony_config = merge( $config->{colony}->{ $planets->{$pid} } || {}, $config->{colony}->{_default_} );

            next if ( not exists $colony_config->{priorities} or $colony_config->{exclude} );
            $self->{current}->{planet_id} = $pid;
            $self->{current}->{config}    = $colony_config;
            $self->govern();
        }
        $self->coordinate_pushes();
        Games::Lacuna::Client::PrettyPrint::ship_report($self->{ship_info},$self->{config}->{ship_info_sort}) if defined $self->{ship_info};
        trace(sprintf("%d RPC calls this run",$self->{client}->{total_calls})) if ($self->{config}->{verbosity}->{trace});
        if ( $self->{config}->{dry_run} ) {
            message("Dry run complete.");
            return;
        }
        my $next_action_in = min( grep { $_ > time } values %{ $self->{next_action} } ) - time;
        if ( defined $next_action_in && ( $next_action_in + time ) < ( $config->{keepalive} + $start_time ) ) {
            if ( $next_action_in <= 0 ) {
                $do_keepalive = 0;
            }
            else {
                my $nat_time = ptime($next_action_in);
                trace("Expecting to govern again in $nat_time or so, sleeping...") if ($self->{config}->{verbosity}->{trace});
                sleep( $next_action_in + 5 );
                $do_keepalive = 1;
            }
        }
    } while ($do_keepalive);

    $self->write_building_cache();
}

sub govern {
    my $self = shift;
    my ($pid, $cfg) = @{$self->{current}}{qw(planet_id config)};
    my $client = $self->{client};

    my $result  = $self->{client}->body( id => $pid )->get_buildings();
    my $surface_image = $result->{body}->{surface_image};
    $surface_image =~ s/^surface-//g;
    my $details = $result->{buildings};
    my $status  = $result->{status}->{body};
    $self->{status}->{$pid} = $status;

    Games::Lacuna::Client::PrettyPrint::show_bar('*');
    message("Governing ".$status->{name}) if ($self->{config}->{verbosity}->{message});
    Games::Lacuna::Client::PrettyPrint::show_status($status) if ($self->{config}->{verbosity}->{summary});
    Games::Lacuna::Client::PrettyPrint::surface($surface_image,$details) if ($self->{config}->{verbosity}->{surface_map});
    $self->{building_cache}->{body}->{$pid} = $details; 
    for my $bid (keys %{$self->{building_cache}->{body}->{$pid}}) {
        $self->{building_cache}->{body}->{$pid}->{$bid}->{pretty_type} = 
            Games::Lacuna::Client::Buildings::type_from_url( $self->{building_cache}->{body}->{$pid}->{$bid}->{url} );
    }

    if ($self->{config}->{verbosity}->{production}) {
        Games::Lacuna::Client::PrettyPrint::production_report(map { $self->building_details($pid,$_) } keys %$details);
    }


    $status->{happiness_capacity} = $cfg->{resource_profile}->{happiness}->{storage_target} || 1;
   
    for my $res (qw(food ore water energy happiness waste)) {
        my ( $amount, $capacity, $rate ) = @{$status}{ 
            $res eq 'happiness' ? 'happiness' : "$res\_stored", 
            "$res\_capacity", 
            "$res\_hour"
        };
        $rate += 0.00001;
        my $remaining            = $capacity - $amount;
        $status->{full}->{$res}  = $remaining / $rate;
        $status->{empty}->{$res} = $amount / ( -1 * $rate );
    }

    $self->{current}->{status} = $status;

    # Check the size of the build queue
    my $max_queue = 1;
    my ($dev_ministry) = $self->find_buildings('Development');
    if ($dev_ministry) {
        $max_queue = $self->building_details($pid,$dev_ministry->{building_id})->{level} + 1;
    }

    my $current_queue = scalar grep { exists $_->{pending_build} } values %$details;
    $self->{current}->{build_queue_remaining} = $max_queue - $current_queue;
    $self->{next_action}->{$pid} = max(map { $_->{pending_build}->{seconds_remaining} + time } values %$details);
    if ($current_queue == $max_queue) {
        warning("Build queue is full on ".$self->{current}->{status}->{name}) if ($self->{config}->{verbosity}->{warning});
    } 

    for my $priority (@{$cfg->{priorities}}) {
        trace("Priority: $priority") if ($self->{config}->{verbosity}->{trace});
        $self->$priority();
    }

    if ($dev_ministry) {
        ### If we have a build queue, sleep till the waste queue empties or the building
        ### queue empties, whichever is first.
        my $next_build = max(map { $_->{seconds_remaining} } @{$dev_ministry->view->{build_queue}});
        $self->set_next_action_if_sooner( $next_build + time() );
    }
}

sub coordinate_pushes {
    my $self = shift;
    my $info = $self->{push_info};
    my $min  = $self->{config}->{push_minimum_load};

    $Data::Dumper::Sortkeys = 1;
    #print Dumper $info;

    delete $self->{trade_ships};
    $self->{sent_ships} = [];
    trace("Requiring minimum load of $min x capacity to make a push") if ($self->{config}->{verbosity}->{trace});
    $self->coordinate_push_mode($info,$min,1);  # Overload pushes
    $self->coordinate_push_mode($info,$min);    # Request pushes
}

sub coordinate_push_mode {
    my ( $self, $info, $min, $mode ) = @_;    # $mode is true for overload

    for my $pid ( keys %$info ) {
        for my $res ( keys %{ $info->{$pid} } ) {
            next if ( $mode && $info->{$pid}->{$res}->{overload} == 0 );
            my $reqd = $info->{$pid}->{$res}->{ $mode ? 'overload' : 'requested' };
            if ( $reqd > 0 ) {
                trace(sprintf("%s would like to %s %s %s",
                    $self->{planet_names}->{$pid},
                    ($mode ? 'get rid of' : 'ask for'),
                    $reqd,
                    $res)) if ($self->{config}->{verbosity}->{trace});
                my $candidate;
                for my $other ( keys %$info ) {
                    next if ( $other == $pid );
                    my $orig = $mode ? $pid   : $other;
                    my $dest = $mode ? $other : $pid;

                    my $avail = $mode ? min( $info->{$other}->{$res}->{space_left}, $reqd ) : min( $info->{$other}->{$res}->{available} , $reqd ); 
                    my @ships;
                    if( $info->{$orig}->{trade} ){
                        @ships = defined $self->{trade_ships}->{$orig}
                            ? (grep { my $s=$_; not any { $s->{id} == $_ } @{$self->{sent_ships}} } @{$self->{trade_ships}->{$orig}})
                            : @{ $info->{$orig}->{trade}->get_trade_ships()->{ships} };
                    }
                    $self->{trade_ships}->{$orig} = [@ships];

                    if ( defined $self->{config}->{push_ships_named} ) {
                        my $name_match = $self->{config}->{push_ships_named};
                        @ships = grep { $_->{name} =~ /$name_match/i } @ships;
                    }
                    @ships = grep { ( $avail / $_->{hold_size} ) >= $min } @ships;
                    for my $ship (@ships) {
                        my $amt_to_ship = $avail > $ship->{hold_size} ? $ship->{hold_size} : $avail;

                        my @items;
                        if ($res eq 'food' or $res eq 'ore') {
                            for my $spec ($res eq 'food' ? $self->food_types : $self->ore_types) {
                                my $has = $mode ? $info->{$pid} : $info->{$other};
                                push @items, { type => $spec, quantity => int(($has->{$spec}->{available} / $has->{$res}->{available}) * $amt_to_ship) };
                            }
                        } else {
                            push @items, { type => $res, quantity => int($amt_to_ship) };
                        }
                        @items = grep { $_->{quantity} > 0 } @items;

                        $ship->{estimated_travel_time} = $self->estimate_travel_time($orig,$dest,$ship->{speed});

                        my $metric = $amt_to_ship / $ship->{estimated_travel_time};
                        if ( $metric > $candidate->{metric} ) {    # Candidate metric is cargo amount / time to destination
                            $candidate->{metric} = $metric;
                            $candidate->{trade}  = $info->{$orig}->{trade};
                            $candidate->{orig}   = $orig;
                            $candidate->{dest}   = $dest;
                            $candidate->{name}   = $ship->{name};
                            $candidate->{ship}   = $ship->{id};
                            $candidate->{items}  = [ @items ];
                        }
                    }
                }
                if ( defined $candidate ) {
                    action(
                        sprintf "Pushing from %s to %s with %s carrying: %s\n",
                        $self->{planet_names}->{ $candidate->{orig} },
                        $self->{planet_names}->{ $candidate->{dest} },
                        $candidate->{name}, join(q{, },map { $_->{quantity}." ".$_->{type} } @{$candidate->{items}})
                    );
                    if (not $self->{config}->{dry_run}) {
                        $info->{ $candidate->{orig} }->{trade}->push_items( $candidate->{dest}, $candidate->{items}, { ship_id => $candidate->{ship} } );
                    }
                    push @{$self->{sent_ships}}, $candidate->{ship};
                }
                else {
                    trace("No suitable pushes found.") if ($self->{config}->{verbosity}->{trace});
                }
            }
        }
    }
}

sub repairs {
    # Not yet implemented.
}

sub production_crisis {
    my $self = shift;
    $self->resource_crisis('production');
}

sub storage_crisis {
    my $self = shift;
    $self->resource_crisis('storage');
}

sub resource_crisis {
    my ($self, $type) = @_;
    my $client = $self->{client};
    my ($status, $cfg) = @{$self->{current}}{qw(status config)};

    # Stop without processing if the build queue is full.
    if(defined $self->{current}->{build_queue_remaining} &&
        $self->{current}->{build_queue_remaining} == 0) {
        return;
    }

    my $key = $type eq 'production' ? 'empty' : 'full';

    for my $res (sort { $status->{$key}->{$a} <=> $status->{$key}->{$b} } keys %{$status->{$key}}) {
        my $time_left = $status->{$key}->{$res};
        if ( $time_left < $cfg->{crisis_threshhold_hours} && $time_left >= 0) {
            warning(sprintf("%s crisis detected for %s: Only %s remain until $key, less than %s threshhold.",
                ucfirst($type), uc($res), phours($time_left), phours($cfg->{crisis_threshhold_hours}))) if $self->{config}->{verbosity}->{warning};

            # Attempt to increase production/storage
            my $upgrade_succeeded = $self->attempt_upgrade_for($res, $type, 1 ); # 1 for override, this is a crisis.

            if ($upgrade_succeeded) {
                my $bldg_data = $self->{building_cache}->{body}->{$status->{id}}->{$upgrade_succeeded};
                action(sprintf("Upgraded %s, %s (Level %s)",$upgrade_succeeded,$bldg_data->{pretty_type},$bldg_data->{level}));
            } else {
                warning("Could not find any suitable buildings to upgrade") if $self->{config}->{verbosity}->{warning};

            }
            # If we could not increase production, attempt to reduce consumption (!!)
            if ($type eq 'production' and not $upgrade_succeeded and $cfg->{allow_downgrades}) {
                # Not yet implemented.
            }
        }
    }

}

sub construction {
    # Not yet implemented.
}

sub estimate_travel_time {
    my ($self, $orig, $dest, $speed) = @_;

    my ($ox, $oy) = ($self->{status}->{$orig}->{x}, $self->{status}->{$orig}->{y});
    my ($dx, $dy) = ($self->{status}->{$dest}->{x}, $self->{status}->{$dest}->{y});

    return int((sqrt((($ox-$dx)**2) + (($oy-$dy)**2))/($speed/100))*3600);
}

sub production_upgrades {
    my $self = shift;
    $self->_resource_upgrader('production');
}

sub storage_upgrades {
    my $self = shift;
    $self->_resource_upgrader('storage');
}

sub resource_upgrades {
    my $self = shift;
    $self->production_upgrades;
    $self->storage_upgrades;
}

sub _resource_upgrader {
    my ($self, $type) =  @_;
    my ($status, $cfg) = @{$self->{current}}{qw(status config)};
    my @reslist = qw(food ore water energy waste happiness);

    # Stop without processing if the build queue is full.
    if((defined $self->{current}->{build_queue_remaining}) &&
        ($self->{current}->{build_queue_remaining} <= $cfg->{reserve_build_queue})) {
        warning(sprintf("Aborting, %s slots in build queue <= %s reserve slots specified",
            $self->{current}->{build_queue_remaining},
            $cfg->{reserve_build_queue})) if $self->{config}->{verbosity}->{warning};
        return;
    }

    my $profile = normalized_profile($cfg->{profile},$type,@reslist);
    my @selected = $self->select_resource($status,$profile,$type eq 'production' ? 'hour' : 'capacity',@reslist);
    for my $selected ( @selected ){
        my $upgrade_succeeded = $self->attempt_upgrade_for($selected, $type ); # 1 for override, this is a crisis.

        if ($upgrade_succeeded) {
            my $bldg_data = $self->{building_cache}->{body}->{$status->{id}}->{$upgrade_succeeded};
            action(sprintf("Upgraded %s, %s (Level %s)",$upgrade_succeeded,$bldg_data->{pretty_type},$bldg_data->{level}));
            last;
        } else {
            warning("Could not find any suitable buildings for $selected to upgrade") if $self->{config}->{verbosity}->{warning};

        }
    }
}

sub normalized_profile {
    my $prof = shift;
    my $type = shift;
    my $nprod = {};
    my @reslist = @_;
    my $sum = 0;
    for my $res (@reslist) {
        my $val = defined $prof->{$res}->{$type} ? $prof->{$res}->{$type} : $prof->{_default_}->{$type};
        if (not defined $val) {
            $val = defined $prof->{$res}->{production} ? $prof->{$res}->{production} : $prof->{_default_}->{production};
        }
        $sum += $nprod->{$res} = $val;
    }
    if ($sum == 0) {
        return { map { $_ => 0} @reslist };
    }
    return { map { $_ => (abs($nprod->{$_}/$sum)) } @reslist };
}

sub select_resource {
    my ($self, $status, $profile, $key_type, @reslist) = @_;

    my $hourly_total = sum(map { abs($_) } @{$status}{ map { "$_\_$key_type" } @reslist});
    my $max_discrepancy;
    my $selected;

    my %discrepancy;
    for my $res (@reslist) {
        # Can't store happiness
        next if ($res eq 'happiness' and $key_type eq 'capacity');
        my $prop = $status->{"$res\_$key_type"} / $hourly_total;
        $discrepancy{$res} = $profile->{$res} - $prop;
    }
    my @selected = reverse sort { $discrepancy{$a} <=> $discrepancy{$b} } grep { $discrepancy{$_} > 0 } keys %discrepancy;
    for my $selected (@selected){
        trace(
            sprintf(
                "Discrepancy of %2d%% ($key_type) detected for %s.",
                $discrepancy{$selected}*100, $selected
            )
        ) if ($self->{config}->{verbosity}->{trace});
    }
    return @selected;
}

sub other_upgrades {
    # Not yet implemented.
}

sub ship_report {
    my $self = shift;
    my $pid = $self->{current}->{planet_id};
    my ($spaceport) = $self->find_buildings('SpacePort');
    return if not ($spaceport);
    $self->{ship_info}->{$self->{planet_names}->{$pid}} = $spaceport->view_all_ships->{ships};
}

sub recycling {
    my ($self, $type) =  @_;
    my ($pid, $status, $cfg) = @{$self->{current}}{qw(planet_id status config)};
    my @reslist = qw(food ore water energy waste happiness);

    if ($status->{waste_hour} < 0 and not $cfg->{recycle_when_negative}) {
        trace("Aborting recycling, current waste production is negative.") if ($self->{config}->{verbosity}->{trace});
        return;
    }

    my $concurrency = $cfg->{profile}->{waste}->{concurrency} || 1;

    my @recycling = $self->find_buildings('WasteRecycling');
    if (not scalar @recycling) {
        warning($status->{name} . " has no recycling centers") if $self->{config}->{verbosity}->{warning};
        return;
    }

    if ($status->{waste_stored} < $cfg->{profile}->{waste}->{recycle_above}) {
        trace("Insufficient waste to trigger recycling.") if ($self->{config}->{verbosity}->{trace});
        return;
    }

    my @available = grep { not exists $self->building_details($pid,$_->{building_id})->{work} } @recycling;
    my $jobs_running = (scalar @recycling - scalar @available);
    trace("$jobs_running recycling jobs running on ".$status->{name}) if ($self->{config}->{verbosity}->{trace});

    do {
        ### If a job will finish before our next run, lets set ourselves up to run again.
        my @working = grep { defined $self->building_details($pid, $_->{building_id})->{work} } @recycling;
        my @recycle_times = map {
            $self->building_details($pid, $_->{building_id})->{work}->{seconds_remaining}
        } @working;
        $self->set_next_action_if_sooner( $_ + time() ) for @recycle_times;
    };

    if ($jobs_running >= $concurrency) {
        warning("Maximum (or more) concurrent recycling jobs ($concurrency) are running, aborting.") if $self->{config}->{verbosity}->{warning};
        return;
    }

    my ($center) = @available;
    # Resource selection based on criteria.  Default is 'split'.
    my $to_recycle = $status->{waste_stored} - $cfg->{profile}->{waste}->{recycle_reserve};
    if ($to_recycle <= 0) {
        warning("Confusing directives:  Can't recycle if recycle_reserve > recycle_above") if $self->{config}->{verbosity}->{warning};
        return;
    }
    my $max_recycle = $center->view->{recycle}->{max_recycle};
    $to_recycle = $max_recycle if ($to_recycle > $max_recycle);

    my $criteria = $cfg->{profile}->{waste}->{recycle_selection} || 'split';
    my @rr = qw(water ore energy);
    my %recycle_res;
    my $res = undef;
    if ($criteria eq 'split') { # Split evenly
        @recycle_res{@rr}= (int($to_recycle/3)) x 3;
    } 
    elsif (any {$criteria eq $_} @rr) { # Named resource only
        $res = $criteria;
    }
    elsif ($criteria eq 'full') { # Whichever will fill up last
        ($res) = sort { $status->{full}->{$b} <=> $status->{full}->{$a} } @rr;
    }
    elsif ($criteria eq 'empty') { # Whichever will empty first
        ($res) = sort { $status->{empty}->{$a} <=> $status->{empty}->{$b} } @rr;
    }
    elsif ($criteria eq 'storage') { # Whichever we have least of
        ($res) = sort { $status->{"$a\_stored"} <=> $status->{"$b\_stored"} } @rr;
    }
    elsif ($criteria eq 'production') { # Whichever we product least of
        ($res) = sort { $status->{"$a\_hour"} <=> $status->{"$b\_hour"} } @rr;
    } else {
        warning("Unknown recycling_selection: $criteria") if $self->{config}->{verbosity}->{warning};
        return;
    }
    if (defined $res) {
        $recycle_res{$res} = $to_recycle;
    }
    eval {
        my $center_view;
        if (not $self->{config}->{dry_run}) {
            $center_view = $center->recycle(@recycle_res{@rr});
        }
        $self->set_next_action_if_sooner(
            $center_view->{recycle}{seconds_remaining}
        );
    };
    if ($@) {
        warning("Problem recycling: $@") if $self->{config}->{verbosity}->{warning};
    } else {
        action(sprintf("Recycling Initiated: %d water, %d ore, %d energy",@recycle_res{@rr}));
    }
}

sub set_next_action_if_sooner {
    my $self = shift;
    my $time = shift;
    my $pid = $self->{current}{planet_id};
    my $ctime= $self->{next_action}->{$pid};
    return if not defined $time;
    $self->{next_action}->{$pid} =
        (defined $ctime and $ctime < $time) ? $ctime : $time;
    return $self->{next_action}->{$pid};
}

sub pushes {  # This stage merely analyzes what we have or need.  Actual pushes occur in run().
    my $self = shift;
    my ($pid, $status, $cfg) = @{$self->{current}}{qw(planet_id status config)};
    my @reslist = qw(food ore water energy waste);

    my @trade = $self->find_buildings('Trade');
    my $stored;

    # Consider Excess
    if (scalar @trade) {  # Need a Trade Ministry to consider pushing from here.
        $self->{push_info}->{$pid}->{trade} = $trade[0];
        $stored = $trade[0]->get_stored_resources->{resources};

        for my $res (@reslist) {
            my $profile = merge($cfg->{profile}->{$res} || {},$cfg->{profile}->{_default_});
            my $have = $status->{"$res\_stored"};
            my $available = $have - ($status->{"$res\_capacity"} * $profile->{push_above});
            if (defined $profile->{overload_above} and
                (($status->{"$res\_stored"} / $status->{"$res\_capacity"}) >= $profile->{overload_above})) {
                $self->{push_info}->{$pid}->{$res}->{overload} = $available;
            }
            if ($available > 0) {
                if ($res eq 'food' or $res eq 'ore') {
                   for my $spec ($res eq 'food' ? $self->food_types : $self->ore_types) {
                        my $spec_profile = merge($cfg->{profile}->{$res}->{specifics}->{$spec} || {},
                                                    $cfg->{profile}->{$res}->{specifics}->{_default_});
                        my $spec_available = $stored->{$spec} - $spec_profile->{push_above};
                        if ($spec_available > 0) {
                            $self->{push_info}->{$pid}->{$spec}->{available} = $spec_available;
                        }
                   } 
                   $self->{push_info}->{$pid}->{$res}->{available} = sum(map { $_->{available} } @{ $self->{push_info}->{$pid} }{$res eq 'food' ? $self->food_types : $self->ore_types});
                } else {
                   $self->{push_info}->{$pid}->{$res}->{available} = $available;
                }
            }
        }

    } else {
        trace("Can't push from here without a Trade Ministry") if ($self->{config}->{verbosity}->{trace});
    }

    # Consider Need
    for my $res (@reslist) {
        my $profile = merge($cfg->{profile}->{$res} || {},$cfg->{profile}->{_default_});
        $self->{push_info}->{$pid}->{$res}->{space_left} = ($status->{"$res\_capacity"} * $profile->{requested_level}) - $status->{"$res\_stored"};
        if (($status->{"$res\_stored"}/$status->{"$res\_capacity"}) < $profile->{request_below}) {
            my $amt = int($status->{"$res\_capacity"} * $profile->{requested_level}) - $status->{"$res\_stored"};
            $self->{push_info}->{$pid}->{$res}->{requested} = $amt;
        }
        if (scalar @trade) { # Consider specific needs
            if (not defined $stored) {
                $stored = $trade[0]->get_stored_resources->{resources};
            }
            for my $spec ($res eq 'food' ? $self->food_types : $self->ore_types) {
                my $spec_profile = merge($profile->{specifics}->{$spec} || {},
                                         $profile->{specifics}->{_default_});
                next if ($spec_profile->{requested_amount} == 0);
                my $amt = $spec_profile->{requested_amount} - $stored->{$spec};
                $self->{push_info}->{$pid}->{$spec}->{requested} = $amt;    
            }
        } 
    }
}

sub building_details {
    my ($self, $pid, $bid) = @_;

    if ((time - $self->{building_cache}->{cache_time} > $self->{config}->{cache_duration})
        or
        ($self->{building_cache}->{body}->{$pid}->{$bid}->{level} ne $self->{building_cache}->{building}->{$bid}->{level})
        or
        (not defined $self->{building_cache}->{building}->{$bid}->{pretty_type})) {
        $self->refresh_building_details($self->{building_cache}->{body}->{$pid},$bid);
    }
    delete $self->{building_cache}->{building}->{$bid}->{work};
    delete $self->{building_cache}->{building}->{$bid}->{pending_build};
    return merge($self->{building_cache}->{body}->{$pid}->{$bid},$self->{building_cache}->{building}->{$bid});
}

sub load_building_cache {
    my ($self) = shift;
    my $cache_file = $self->{config}->{cache_dir} . "/buildings.json";
    my $data;
    if (-e $cache_file) {
        local $/;
        eval {
            open( my $fh, '<', $cache_file );
            my $json_text   = <$fh>;
            $data = from_json( $json_text );
            close $fh;
        };
    }
    if (not defined $data) {
        trace("No cache file found") if ($self->{config}->{verbosity}->{trace});
    } else {
        trace("Loading building cache") if ($self->{config}->{verbosity}->{trace});
        $self->{building_cache} = $data;
    }
}

sub refresh_building_cache {
    my ($self) = shift;

    for my $pid (keys %{$self->{status}->{empire}->{planets}}) {
        my $details = $self->{client}->body( id => $pid )->get_buildings()->{buildings};
        $self->{building_cache}->{body}->{$pid} = $details;
        $self->refresh_building_details($details,$_) for ( keys %$details );
    }
    $self->write_building_cache();
}

sub refresh_building_details {
    my ($self, $details, $bldg_id) = @_;
    my $client = $self->{client};
    
    if (not exists $details->{$bldg_id}->{pretty_type}) {
        $details->{$bldg_id}->{pretty_type} = 
            Games::Lacuna::Client::Buildings::type_from_url( $details->{$bldg_id}->{url} );
    }

    if ( not defined $details->{$bldg_id}->{pretty_type} ) {
        warning("Building $bldg_id has unknown type (".$details->{$bldg_id}->{url}.").\n") if $self->{config}->{verbosity}->{warning};
        return;
    }

    $self->{building_cache}->{building}->{$bldg_id} = $client->building( id => $bldg_id, type => $details->{$bldg_id}->{pretty_type} )->view()->{building};
    $self->{building_cache}->{building}->{$bldg_id}->{pretty_type} = $details->{$bldg_id}->{pretty_type};
}

sub write_building_cache {
    my ($self) = shift;
    
    my $cache_file = $self->{config}->{cache_dir} . "/buildings.json";
    
    $self->{building_cache}->{cache_time} = time;

    if(open( my $fh, '>', $cache_file)) { 
        print $fh to_json($self->{building_cache});
        close $fh;
    }
}

sub attempt_upgrade_for {
    my ($self,$resource,$type,$override) = @_;
    my ($status, $pid, $cfg) = @{$self->{current}}{qw(status planet_id config)};

    my @all_options = $self->resource_buildings($resource,$type);

    my %build_above = map { $_ => (($cfg->{profile}->{$_}->{build_above} > 0) ?
                $cfg->{profile}->{$_}->{build_above} :
                $cfg->{profile}->{_default_}->{build_above})
        } qw(food ore water energy);

    Games::Lacuna::Client::PrettyPrint::upgrade_report(\%build_above,map { $self->building_details($pid,$_->{building_id}) } @all_options)
        if ($self->{config}->{verbosity}->{upgrades});

    # Abort if an upgrade is in progress.
    for my $opt (@all_options) {
        if (any {$opt->{building_id} == $_->{building_id}} @{$self->{current}->{build_queue}}) {
            trace(sprintf("Upgrade already in progress for %s, aborting.",$opt->{building_id})) if ($self->{config}->{verbosity}->{trace});
            return;
        }
    }

    my @upgrade_options;

    my @options = part {
        my $bid = $_->{building_id};
        (
            not any { ($status->{"$_\_stored"} - $self->building_details($pid,$bid)->{upgrade}->{cost}->{$_}) 
                < $build_above{$_} 
            } qw(food ore water energy)
            and (not ($status->{waste_stored} + $self->building_details($pid,$bid)->{upgrade}->{cost}->{waste})
                > $status->{waste_capacity})
        )+0;
    } @all_options;

    @options = map { ref $_ ? $_ : [] } @options[0,1];

    if ($override) { # Include both sets of options, non-override first
      @upgrade_options = (@{$options[1]},@{$options[0]});
    } else {
      @upgrade_options = @{$options[1]};
    }

    my $upgrade_succeeded = 0;
    for my $upgrade (@upgrade_options) {
        eval { 
            my $details = $self->building_details($pid,$upgrade->{building_id});
            trace(sprintf("Attempting to upgrade %s, %s (Level %s)",$details->{id},$details->{pretty_type},$details->{level})) if ($self->{config}->{verbosity}->{trace});
            if (not $self->{config}->{dry_run}) {
               $upgrade->upgrade();
            } else {

               my $upg_details = $upgrade->view->{building}->{upgrade};
               if (not $upg_details->{can}) {
                 die "(dry run)" . join(q{: },@{$upg_details->{reason}});
               }
            }
        };
        if (not $@) {
            $upgrade_succeeded = $upgrade->{building_id};
        } else {
            trace("Upgrade failed: $@") if ($self->{config}->{verbosity}->{trace});
        }
        last if $upgrade_succeeded;
    }

    # Decrement remaining build queue if upgrade succeeded.
    $self->{current}->{build_queue_remaining}-- if ($upgrade_succeeded);
    return $upgrade_succeeded;
}

sub resource_buildings {
    my ($self,$res,$type) = @_;
    my ($pid, $status, $cfg) = @{$self->{current}}{qw(planet_id status config)};

    my @pertinent_buildings;
    for my $bid (keys %{$self->{building_cache}->{body}->{$pid}}) {
        my $pertinent = 0;
        my $details = $self->building_details($pid,$bid);
        my $pretty_type = $details->{pretty_type};
        my $meta_type = meta_type($pretty_type);
        next if (not any { $_ eq $meta_type } qw(food ore water energy waste storage happiness));
        if ($type eq 'storage' && $details->{"$res\_capacity"} > 0) {
            $pertinent = ($pretty_type eq 'PlanetaryCommand') ? $cfg->{pcc_is_storage} : 1;
        } elsif ($type eq 'production' && $details->{"$res\_hour"} > 0) {
            $pertinent = 1;
        } elsif ($type eq 'consumption' && $details->{"$res\_hour"} < 0) {
            $pertinent = 1;
        }
        push @pertinent_buildings, $self->{client}->building( 
                id => $bid, 
                type => $pretty_type,
            ) if $pertinent;
    }
    return sort { $self->pertinence_sort($res,$cfg->{upgrade_selection},$type,$a,$b) } @pertinent_buildings;
}

sub find_buildings {
    my ($self, $type) = @_;
    my $pid  = $self->{current}->{planet_id};
    my @retlist;

    for my $bid (keys %{$self->{building_cache}->{body}->{$pid}}) {
        my $pretty_type = $self->{building_cache}->{body}->{$pid}->{$bid}->{pretty_type};
        push @retlist, $self->{client}->building( id => $bid, type => $pretty_type ) if $pretty_type eq $type;
    }
    return @retlist;
}

sub pertinence_sort {
    my ($self,$res,$preference,$type,$left,$right) = @_;
    $preference = 'most_effective' if not defined ($preference);
    my $cache = $self->{building_cache}->{building};

    my $sort_types = {
        'most_effective' => {
            'storage'     => sub { return $cache->{ $right->{building_id} }->{"$res\_capacity"} <=> $cache->{ $left->{building_id} }->{"$res\_capacity"} },
            'production'  => sub { return $cache->{ $right->{building_id} }->{"$res\_hour"} <=> $cache->{ $left->{building_id} }->{"$res\_hour"} },
            'consumption' => sub { return $cache->{ $left->{building_id} }->{"$res\_hour"} <=> $cache->{ $right->{building_id} }->{"$res\_hour"} },
        },
        'least_effective' => {
            'storage'     => sub { return $cache->{ $left->{building_id} }->{"$res\_capacity"} <=> $cache->{ $right->{building_id} }->{"$res\_capacity"} },
            'production'  => sub { return $cache->{ $left->{building_id} }->{"$res\_hour"} <=> $cache->{ $right->{building_id} }->{"$res\_hour"} },
            'consumption' => sub { return $cache->{ $left->{building_id} }->{"$res\_hour"} <=> $cache->{ $right->{building_id} }->{"$res\_hour"} },
        },
        'most_expensive'  => sub { return sum_keys( $cache->{ $right->{building_id} }->{upgrade}->{cost} ) <=> sum_keys( $cache->{ $left->{building_id} }->{upgrade}->{cost} ) },
        'least_expensive' => sub { return sum_keys( $cache->{ $left->{building_id} }->{upgrade}->{cost} ) <=> sum_keys( $cache->{ $right->{building_id} }->{upgrade}->{cost} ) },
        'highest_level'   => sub { return $cache->{ $right->{building_id} }->{level} <=> $cache->{ $left->{building_id} }->{level} },
        'lowest_level'    => sub { return $cache->{ $left->{building_id} }->{level} <=> $cache->{ $right->{building_id} }->{level} },
        'slowest'         => sub { return $cache->{ $right->{building_id} }->{upgrade}->{cost}->{time} <=> $cache->{ $left->{building_id} }->{upgrade}->{cost}->{time} },
        'fastest'         => sub { return $cache->{ $left->{building_id} }->{upgrade}->{cost}->{time} <=> $cache->{ $right->{building_id} }->{upgrade}->{cost}->{time} },
    };
    return (ref $sort_types->{$preference} eq 'HASH') ? $sort_types->{$preference}->{$type}->() : $sort_types->{$preference}->();
}

sub upgrade_cost {
    my $hash = shift;
    return sum(@{$hash}{qw(food ore water energy waste)});
}

sub food_types {
    return qw(algae apple bean beetle bread burger chip cheese cider corn fungus lapis meal milk pancake pie potato root shake soup syrup wheat);
}

sub ore_types {
    return qw(anthracite bauxite beryl chalcopyrite chromite fluorite galena goethite gold gypsum halite kerogen magnetite methane monazite rutile sulfur trona uraninite zircon);
}

sub meta_type {
    my $type = shift;
    my $meta_types = {
        command => [qw{
            Archaeology
            Development
            Embassy
            Intelligence
            Network19
            Observatory
            Park
            PlanetaryCommand
            Security
            Shipyard
            SpacePort
            Trade
            Transporter
            Capitol
            CloakingLab
            Espionage
            GasGiantLab
            GasGiantPlatform
            GeneticsLab
            MissionCommand
            MunitionsLab
            Oversight
            PilotTraining
            Propulsion
            Stockpile
            TerraformingLab
            TerraformingPlatform
            University
        }],
        happiness => [qw{
            Entertainment
            LuxuryHousing
        }],
        food => [qw{
            Algae
            Apple
            Bean
            Beeldeban
            Bread
            Burger
            Cheese
            Chip
            Cider
            Corn
            CornMeal
            Dairy
            Denton
            Lapis
            Malcud
            Pancake
            Pie
            Potato
            Shake
            Soup
            Syrup
            Wheat
        }],

        glyph => [qw{
            Crater
            CrashedShipSite
            EssentiaVein
            GeoThermalVent
            InterDimensionalRift
            KalavianRuins
            Lake
            Lagoon
            LibraryOfJith
            Grove
            MassadsHenge
            NaturalSpring
            OracleOfAnid
            RockyOutcrop
            Ravine
            Sand
            TempleOfTheDrajilites
            Volcano
        }],
        energy => [qw{
            Fission
            Fusion
            Geo
            HydroCarbon
            Singularity
            WasteEnergy
        }],
        ore => [qw{
            Mine
            OreRefinery
            WasteDigester
            MiningMinistry
        }],
        waste => [qw{
            WasteTreatment
            WasteRecycling
        }],
        water => [qw{
            WaterProduction
            WaterPurification
            WaterReclamation
        }],
        storage => [qw{
            WasteSequestration
            EnergyReserve
            WaterStorage
            FoodReserve
            OreStorage
        }],
    };
    for my $k (keys %$meta_types) {
        if (any {$_ eq $type} @{$meta_types->{$k}}) {
            return $k;
        }
    }
}


1;

__END__

=head1 NAME

Games::Lacuna::Client::Governor - A rudimentary configurable module for automation of colony maintenance

=head1 SYNOPSIS

    my $client   = Games::Lacuna::Client->new( cfg_file => $client_config );
    my $governor = Games::Lacuna::Client::Governor->new( $client, $governor_config );
    $governor->run();

=head1 DESCRIPTION

This module implements a rudimentary configurable automaton for maintaining your colonies.  
Currently, this means automation of upgrade and recycling tasks, but more is planned.
The intent is that the automation should be highly configurable, which of course has a cost
of a complex configuration file.

This script makes an effort to do its own crude caching of building data in order to minimize
the number of RPC calls per invocation.  In order to build its cache on first run, this script
will call ->view() on every building in your empire.  This is expensive.  However, after the 
first run, you can expect the script to run between 1-5 calls per colony.  In my tests the
script currently makes about 10-20 calls per invocation for an empire with 4 colonies.  
Running on an hourly cron job, this is acceptable for me.

The building data for any particular building does get refreshed from the server if the
script thinks it looks fishy, for example, if it doesn't have any data for it, or if
the building's level has changed from what is in the cache.

This module has absolutely no tests associated with it.  Use at your own risk.  I'm only
trying to be helpful.  Be kind, please rewind.  Etc. Etc.


=head1 DEPENDENCIES

I depend on Hash::Merge and List::MoreUtils to make the magic happen.  Please provide them.
I also depend on Games::Lacuna::Client (of course), and Games::Lacuna::Client::PrettyPrint,
which was published to this distribution at the same time as me.

=head1 Methods

=head2 new

Takes exactly 2 arguments, the client object built by Games::Lacuna::Client->new, and a
path to a YAML configuration file, described in the L<CONFIGURATION FILE> section below.

=head2 run

Runs the governor script according to configuration.  Note: old behavior which permitted
an argument to force a scan of all buildings has been removed as superfluous and wasteful.

=head1 CONFIGURATION FILE

It's a multi-level data structure.  See F<examples/governor.yml>.

=head2 cache_dir

This is a directory which must be writeable to you.  I will write my
building cache data here.

=head2 cache_duration

This is the maximum permitted age of the cache file, in seconds, before
a refresh is required.  Note the age of the cache file is updated with
each run, so this value may be set high enough that a refresh is never
forced.  Refreshes are pulled on a per-building basis.

=head2 dry_run

If this is true, Governor goes through the motions but does not actually
trigger any actions (such as upgrades, recycling jobs, or pushes).  The
output shows the actions as they would have taken place.  Enabling dry_run
disables keepalive behavior.

=head2 keepalive

This is the window of time, in seconds, to try to keep the governor alive
if more actions are possible.  Basically, if any governed colony's build
queue will be empty before the keepalive window expires, the script will
not terminate, but will instead sleep and wait for that build queue to empty
before once again governing that colony.  Setting this to 0 will
effectively disable this behavior.

=head2 push_minimum_load

This is a proportion, i.e. 0.5 for 50%.  It indicates the minimum amount
of used cargo space to require before a ship will be sent on a push.  
E.g., if set to 0.25, a ship must be at least 25% full of its maximum
cargo capacity or it will not be considered eligible for a push.

=head2 push_ships_named

If defined, ship names must match this substring (case-insensitive) to
be eligible to be used for pushes.  This is an easy to to tell the governor
which ships it can utilize.

=head2 verbosity

Not all of the 'verbosity' keys are currently implemented.  If any are
true, messages of that type are output to standard output.

=head3 action

Messages notifying you that some action has taken place.

=head3 construction

Outputs a construction report for each colony (not yet implemented)

=head3 message

Messages which are informational in nature.  One level above trace.

=head3 production

Outputs a production report for each colony (not yet implemented)

=head3 pushes

Outputs a colony resource push analysis (not yet implemented)

=head3 storage

Outputs a storage report for each colony (not yet implemented)

=head3 summary

Outputs a resource summary for each colony

=head3 surface_map

Too much time on my hands.  Outputs an ASCII version of the planet surface map.

=head3 trace

Outputs detailed information during various activities.

=head3 upgrades

Outputs an available upgrade report when analyzing upgrades.

=head3 warning

Messages that an exceptional condition has been detected.

=head2 colony

See L<COLONY-SPECIFIC CONFIGURATION>.  Yes, a 'colony' key should literally
exist and contain further hashes.

=head1 COLONY-SPECIFIC CONFIGURATION

The next level beneath the 'colony' key should name (by name!) each colony
on which the governor should operate, and provide configuration for it.
If a _default_ key exists (underscores before and after), this will be
applied to all existent colonies unless overridden by colony-specific
settings.

=head2 allow_downgrades

(Not yet implemented).  Allow downgrading buildings if negative production 
levels are causing problems.  True or false.

=head2 crisis_threshhold_hours

A number of hours, decimals allowed.  

If the script detects that you will exceed
your storage capacity for any given resource in less than this amount of time,
a "storage crisis" condition is triggered which forces storage upgrades for your
resources.

If the script detects that your amount of this resource will drop to zero
in less than this amount of time, a "production crisis" condition is 
triggered which forces production upgrades for those resources.

=head2 exclude

If this is true for any particular colony which would otherwise be governed,
the governor will skip this colony and perform no actions.

=head2 pcc_is_storage

If true, the Planetary Command Center is considered a regular storage
building and will be upgraded along with others if storage is needed.
Otherwise, it will be ignored for purposes of storage upgrades.

=head2 priorities

This is a list of identifiers for each of the actions the governor
will perform.  They are performed in the order specified.  Currently
implemented values include:

production_crisis, storage_crisis, resource_upgrades, production_upgrades,
storage_upgrades, recycling, pushes, ship_report

Note: resource_upgrades performs both a production_upgrades and storage_upgrades priority.

To be implemented are:

repairs, construction, other_upgrades

=head2 profile

See RESOURCE PROFILE CONFIGURATION below.  Is this getting complicated yet?
It's really not.  Okay, I lie.  Maybe it is.  I don't know anymore, my brain
is a little fried.

=head2 profile_production_tolerance

Not yet implemented.  Will permit deviations from the production profile
to pass without action.

=head2 profile_storage_tolerance

Not yet implemented.  Will permit deviations from the storage profile
to pass without action. 

=head2 recycle_when_negative

If true, recycling jobs will be triggered even if net waste production on
this colony is negative.  The default is that this does not happen.

=head2 reserve_build_queue

If defined, the governor will reserve this many spots at the end
of the build queue for human action (that's you).

=head2 upgrade_selection

This is a string identifier defining how the governor will select which
upgrade to perform when an upgrade is desired.  One of eight possible
values:

=head3 highest_level

The candidate building with the highest building level is selected.

=head3 lowest_level

Vice-versa.

=head3 most_effective

The candidate building which is most effective and producing or storing
the resource in question (i.e., does it most) is selected.

=head3 least_effective

Vice-versa.

=head3 most_expensive

The candidate building which will cost the most in terms of resources + waste produced
is selected.

=head3 least_expensive.

The opposite.

=head3 slowest

The candidate building which will take the longest amount of time to upgrade
is selected.

=head3 fastest

Other way around.

=head1 RESOURCE PROFILE CONFIGURATION

Okay, so this thing looks at your resource profile, as stored under the 'profile' key,
to decide how your resources should be managed.  If a _default_ key exists here, its
settings will apply to all resources (including waste and happiness) unless overridden
by more specific settings.  Note that storage-related configuration is ignored for
happiness.  Otherwise, the keys beneath 'profile' are the names of your resources:

food, ore, water, energy, waste, happiness

=head2 build_above

Attempt to reserve this amount of this resource after any potential builds.  Unless
this is a crisis, we don't do any upgrades that will bring the resource below this
amount in storage.

=head2 production

This is a funny one.  This is compared against the 'production' profile setting for
all other resources.  If, proportionately, we are falling short, this resource is
marked for a production upgrade.  For example, if all resources were set to production:1,
then it would try to make your production of everything per hour (including waste and
happiness) the same.  If you had all at 1 except for Ore at 3, it would try to produce
3 times more ore than everything else.  And so forth.

=head2 storage

Like production (above), but for storage.  If this is not present, the production value
use used instead.

=head2 push_above

Resources above this level are considered eligible for pushing
to more needy colonies.  Also used as the amount to leave behind when pushing
away due to an overload.  This is a proportion between 0 and 1 interpreted as
this amount times your capacity.

=head2 overload_above

Resources above this level are considered "overloaded" and will be given priority
for pushes to other colonies where space is available.  The amount to be shipped
away is everything higher than push_above, see above.  This is a proportion between
0 and 1 interpreted as this amount times your capacity.

=head2 request_below

Resources below this level trigger a push request from colonies where this resource
is available.  This is a proportion between 0 and 1 interpreted as
this amount times your capacity.

=head2 requested_level

When a push is requested, the amount we would like to receive is calculated to be
enough to bring the amount of resource up to this level. This is a proportion 
between 0 and 1 interpreted as this amount times your capacity.

=head2 specifics

For ore and food, you can specify additional parameters for pushing.  Keys beneath
this are specific types of resource, such as 'anthracite' beneath 'ore', and
'apples' beneath 'food'. You can also use the _default_ key beneath here.  For example:

    food:
      specifics:
        _default_:
          push_above: 500

Would specify that you want to keep at least 500 of each individual type of food on hand.

=head3 requested_amount

If you want to accumulate a specific amount of a specific resource, you can specify that
using this option.  If you just want to accumulate as much as possible of a specific resource,
set this to something obscenely high.

=head3 push_above

This functions like the regular push_above, but is a scalar amount, rather than a proportion
of capacity.  I.e., 500 means 500.

=head2 recycle_above

Only relevant for waste.  If above this level, trigger a recycling job (if possible).

=head2 recycle_reserve

Only relevant for waste.  When recycling, leave this amount of waste in storage. 
I.e., don't recycle it all.

=head2 recycle_selection

Only relevant for waste.  Sets a preference for what we want to recycle waste into.
Can be one of:

=head3 water, ore, or energy

Always recycle the full amount into this resource

=head3 split

Always split the amount evenly between the three types

=head3 full

Pick whichever resource will take the most time before it fills storage

=head3 empty

Pick whichever resource will take the least time before emptying

=head3 storage

Pick whichever we have the least in storage

=head3 production

Pick whichever we produce least of

=head1 SEE ALSO

Games::Lacuna::Client, by Steffen Mueller on which this module is dependent.

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>. 

The Games::Lacuna::Client distribution includes two files pertinent to this script. Well, three.  We need 
Games::Lacuna::Client::PrettyPrint for output.

Also, in F<examples>, you've got the example config file in governor.yml, and the example script in governor.pl.

=head1 AUTHOR

Adam Bellaire, E<lt>bellaire@ufl.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut


