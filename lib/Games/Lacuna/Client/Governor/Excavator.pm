#
#===============================================================================
#
#  DESCRIPTION:  Excavator implements the logic to automatically send excavators
#                to look for glyphs (and anything else it happens to find)
#
#===============================================================================

package Games::Lacuna::Client::Governor::Excavator;
use strict;
use warnings qw(all);
use Carp;
use English qw(-no_match_vars);
use Data::Dumper;
use Hash::Merge qw(merge);

{
    use Storable qw(lock_nstore lock_retrieve);
    use Date::Parse qw(str2time);
    use List::MoreUtils qw(minmax uniq any);
    use Games::Lacuna::Client::PrettyPrint qw(trace message warning action ptime phours);
    my $PROBES_PER_PAGE = 25;
    my $SHIPS_PER_PAGE = 25;
    my $PROBES_PER_LVL = 3;

    sub run {
        my $class   = shift;
        my $gov     = shift;
        my ($pid,$config) = @{$gov->{current}}{qw(planet_id config)};
        my $planet = $gov->{planet_names}->{$pid};

        my ($archaeology) = $gov->find_buildings('Archaeology');
        unless ($archaeology) {
            trace("No Archaeology Ministry on $planet, can't build excavators") if ($gov->{config}->{verbosity}->{trace});

            return;
        }
        my $details = $gov->building_details($pid, $archaeology->{building_id});
        unless ($details->{level} >= 11)
        {
            trace("$planet: Archaeology Ministry @ $details->{level}, needs to be at least 11 to build excavators") if ($gov->{config}->{verbosity}->{trace});
            return;
        }

        my $max_excavators = $details->{level} - 10;
        my $active_excavators = scalar keys %{$archaeology->view_excavators()};
        if ($active_excavators >= $max_excavators)
        {
            trace("Archaeology at $planet is at maximum excavators ($active_excavators >= $max_excavators), not trying to send more") if ($gov->{config}->{verbosity}->{trace});
            return;
        }
            trace("Archaeology at $planet is not at maximum excavators ($active_excavators < $max_excavators), trying to send more") if ($gov->{config}->{verbosity}->{trace});

        my $observatory_stars = $gov->{cache}->{observatory_stars};

        unless ($observatory_stars)
        {
            my @observatories = $gov->find_all_buildings('Observatory');
            my @stars;
            foreach my $observatory (@observatories)
            {
                if( $observatory ){
                    do {
                        my $page = 0;
                        while( $page <= 4 ){
                            $page++;
                            my $data = $observatory->get_probed_stars($page);
                            push @stars, @{$data->{stars}};
                            last if $page * $PROBES_PER_PAGE >= $data->{star_count};
                        }
                    };
                }
            }
            #$observatory_stars = $gov->{cache}->{observatory_stars} = \@stars;
            $observatory_stars = \@stars;
        }

        $gov->{_observatory_plugin}{stars}{$pid} = {
            stars       => $observatory_stars,
        };
        my $planet_name = $gov->{status}{$pid}{name};
        trace(scalar @$observatory_stars . " stars to check for excavator from $planet_name") if ($gov->{config}->{excavator}->{trace});

        ### Now find Spaceports.
        my (@spaceports) = $gov->find_buildings('SpacePort');
        my @all_excavators;
        my @ships;
        my @traveling;
        my @excavator_to_port;
        for my $sp ( @spaceports ){
                my $data = $sp->view_all_ships({ "no_paging" => 1 });
                push @all_excavators, grep { $_->{type} eq 'excavator' } @{$data->{ships}};
                push @ships, grep { $_->{task} eq 'Docked' and $_->{type} eq 'excavator' } @{$data->{ships}};
                push @excavator_to_port, map {; $_->{id} => $sp } @ships;
                push @traveling, grep { $_->{task} eq 'Travelling' and $_->{type} eq 'excavator' } @{$data->{ships}};
        }

        # Build more excavators if directed
        my (@shipyards) = $gov->find_buildings('Shipyard');
        my $build_excavators = $config->{build_excavators} || 0;
        my $excavators_to_build = $build_excavators - scalar @all_excavators;
        my $total_excavators = $active_excavators + @all_excavators;

        if ($total_excavators >= $max_excavators)
        {
            trace("Archaeology at $planet is at maximum excavators ($total_excavators > $max_excavators), not building more") if ($gov->{config}->{verbosity}->{trace});
            $excavators_to_build = 0;
        }

        trace(sprintf("$planet: Found %d excavators, configured to build if less than %d found.",scalar @all_excavators,$build_excavators)) if ($gov->{config}->{verbosity}->{trace});
        while ($excavators_to_build > 0) {
            eval {
                $shipyards[0]->build_ship('excavator');
                action("$planet: Building new excavator");
                $excavators_to_build--;
            };
            if ($@) {
                $excavators_to_build = 0; # Stop trying...
                warning("$planet: Unable to build excavator: $@");
            }
        }

        $gov->{_observatory_plugin}{ports}{$pid} = {
            ports => \@spaceports,
            docked => \@ships,
            travel => \@traveling,
            excavator2port => { @excavator_to_port },
        };

        return;
    }

    sub stars {
        my $class = shift;
        my $gov   = shift;
        my $cache_path = $gov->{config}{cache_dir} . "/observatory.stars.stor";

        # https://us1.lacunaexpanse.com
        my $uri = $gov->{client}->{uri};

        return $gov->{_static_stars}{$uri} if $gov->{_static_stars}{$uri};

        # http://us-east-1.lacunaexpanse.com.s3.amazonaws.com/stars.csv
        my $star_uri = "$uri.s3.amazonaws.com/stars.csv";

        require LWP::UserAgent;
        my $ua = LWP::UserAgent->new;
        $ua->ssl_opts(verify_hostname=>0);

        if( -e $cache_path ){
            ### Check file age.
            do {
                my $response = $ua->head($star_uri);
                if( $response->is_error ){
                    warn "Unable to HEAD the static star map: ", $response->status_line, "\n";
                    return;
                }
                my $lastmod = $response->header('Last-Modified');
                if( not $lastmod ){
                    warn "Unable to determine Last-Modified header for static star map.";
                    return;
                }
                my $uri_lastmod = str2time($lastmod);
                my $file_lastmod = $BASETIME + -M $cache_path;
                if( $uri_lastmod >= $file_lastmod ){
                    ### Re-download the file!
                    my $stars = $class->_download_stars($gov, $ua, $star_uri);
                    $gov->{_static_stars}{$uri} = $stars;
                    lock_nstore($gov->{_static_stars}, $cache_path);
                    return $gov->{_static_stars}{$uri};
                }
            };
            eval {
                trace("Excavator is loading cached static star map...") if $gov->{config}->{verbosity}->{trace};
                $gov->{_static_stars} = lock_retrieve( $cache_path );
            };
            warning(
                "Unable to retrieve existing stars map file: $EVAL_ERROR",
            ) if $EVAL_ERROR;
        }

        return $gov->{_static_stars}{$uri} if $gov->{_static_stars}{$uri};

        ### Re-download the file!
        my $stars = $class->_download_stars($gov, $ua, $star_uri);
        $gov->{_static_stars}{$uri} = $stars;
        lock_nstore($gov->{_static_stars}, $cache_path);
        return $gov->{_static_stars}{$uri};
    }

    sub _download_stars {
        my $class = shift;
        my $gov  = shift;
        my $ua   = shift;
        my $star_uri = shift;

        ### Download the file.
        my $response = $ua->get($star_uri);

        if( $response->is_error ){
            warn "Unable to get static star map: ", $response->status_line, "\n";
            return;
        }

        trace("Excavator is downloading static star map...") if ($gov->{config}->{verbosity}->{trace});
        my $raw_csv = $response->decoded_content;
        require Text::CSV;
        my $csv = Text::CSV->new;
        my %stars;
        do { #parse CSV
            open my $fh, "<:encoding(utf8)", \$raw_csv;
            $csv->column_names( $csv->getline($fh) );
            my $i = 1;
            while( my $row = $csv->getline_hr( $fh ) ){
                $stars{ $row->{name} } = $row;
            }
        };
        return \%stars;

    }

    sub post_run {
        my $class = shift;
        my $gov   = shift;
        my $planet = $gov->{planet_names}->{$gov->{current}->{planet_id}};

        my @pids = keys %{ $gov->{_observatory_plugin}{stars} };
        if( not @pids ){
            trace("$planet: No observatories found, aborting.") if ($gov->{config}->{verbosity}->{trace});
            return;
        }


# TODO: we don't need find all observatories above, as this does the job, we just need to make
# everything use the probed stars list
        my %probed_stars;
        ### Identify all probed stars.
        for my $pid ( @pids ){
            for my $star ( @{$gov->{_observatory_plugin}{stars}{$pid}{stars}} ){
                if( exists $probed_stars{$star->{name}} ){
                    my $planet_name = $gov->{planet_names}->{$pid};
        #            warning(sprintf "Star %s has multiple probes! duplicate probe from %s", $star->{name}, $planet_name);
                    next;
                }
                $probed_stars{$star->{name}} = $star;
            }
        }
        $gov->{_observatory_plugin}{probed_stars} = \%probed_stars;

        ### Grab static star data...
        my %stars = %{ $class->stars($gov) || {} };
        if( not scalar keys %stars ){
            warning("Stars map is empty, this is *highly* unlikely.");
            return;
        }

        ### Find all stars that are probed.
        my %valid_target_stars = %probed_stars;

        ### Determine star distances from Colonies.
        my (%planet_distances);
        my %pid_loc = map { $_ => [@{$gov->{status}{$_}}{qw(x y)}]; } keys %{$gov->{status}{empire}{planets}};
        PLANET:
        while( my ($pid, $planet_xy) = each %pid_loc ){
            my ($planet_x, $planet_y) = @$planet_xy;
            if( not defined $planet_x or not defined $planet_y ){
                warning(
                    sprintf "Unable to determine origin of planet %s, x y coords missing",
                        $gov->{status}{empire}{planets}{$pid}
                );
                next PLANET;
            }
            foreach my $star ( values %valid_target_stars ){
                my ($star_x, $star_y) = @{$star}{qw(x y)};
                my $dist = sqrt( ($star_x - $planet_x)**2 + ($star_y - $planet_y)**2 );
                $planet_distances{$pid}{$star->{name}} = $dist;
            }
        }

        ### For each planet, sort the stars based on their distances from it.
        my %distances_by_planet;
        for my $pid ( keys %pid_loc ){

            my $planet = $gov->{status}->{$pid}->{name};
            next unless $planet;
            my $config = merge($gov->{config}{colony}{$planet} || {}, $gov->{config}{colony}{_default_});
            my $order = $config->{excavator}->{order} || 'nearest';

            # nearest first, default order
            my @distances = sort {
                   $planet_distances{$pid}{$a} <=> $planet_distances{$pid}{$b}
                } keys %{ $planet_distances{$pid} };

            if ($order eq 'furthest') {
                @distances = reverse @distances;
            } elsif ($order eq 'random') {
                @distances = fisher_yates_shuffle(\@distances);
            }

            $distances_by_planet{$pid} = \@distances;
        }

        ### Launch ze Excavators!
        $class->search_and_scan($gov, \%planet_distances, \%distances_by_planet);

        return;
    }

    sub search_and_scan {
        my $class = shift;
        my $gov   = shift;
        my $planet_distances    = shift;
        my $distances_by_planet = shift;
        my $stars = $class->stars($gov);

        ### Denote excavators currently in transit.
        my %traveling_excavators = map {
            my $travel = $gov->{_observatory_plugin}{ports}{$_}{travel};
            # If there are multiple excavators to one dest. Don't care at this point.
            # We already informed the user there are duplicates. Let the Humans figure
            # out how best to resolve that.
            map {; $_->{to}{name} => $_; } @$travel;
        } keys %{$gov->{_observatory_plugin}{ports}};

        ### How many excavators are available for us to send?
        my %excavator_cnt;
        my %docked_excavators = map {
            my $docked = $gov->{_observatory_plugin}{ports}{$_}{docked};
            $excavator_cnt{$_}+= scalar @$docked;
            $_ => $docked;
        } keys %{$gov->{_observatory_plugin}{ports}};

        my $dry_run = $gov->{config}{dry_run} ? "[DRYRUN]: " : '';

        ### Select our targets. Naively.
        PLANET:
        for my $pid ( keys %docked_excavators ){
            my $planet = $gov->{status}{$pid}{name};
            my $furthest_stars = $distances_by_planet->{$pid};
            trace("selecting targets for $excavator_cnt{$pid} excavators from $planet from " . scalar @$furthest_stars . " stars") if ($gov->{config}->{excavator}->{trace});
            STAR:
            for my $star ( @{$furthest_stars} ){
                trace("excavator already travelling to star $star") if $traveling_excavators{$star} && ($gov->{config}->{excavator}->{trace});
                next STAR if $traveling_excavators{$star};
#                trace("adding star $star") if ($gov->{config}->{excavator}->{trace});

                my ($excavator_id) = keys %{$gov->{_observatory_plugin}{ports}{$pid}{excavator2port}};
                last STAR if not $excavator_id;
                my $port  = $gov->{_observatory_plugin}{ports}{$pid}{excavator2port}{$excavator_id};

                trace("excavators left: " . scalar keys %{$gov->{_observatory_plugin}{ports}{$pid}{excavator2port}}) if ($gov->{config}->{excavator}->{trace});
                my @target_planets;

                trace("targetting planets of $star") if ($gov->{config}->{excavator}->{trace});
                my $star_data = $gov->{_observatory_plugin}{probed_stars}{$star};

                foreach my $target_planet (@{$star_data->{bodies}})
                {
                    my $target_name = $target_planet->{name};
                    my $last_attempt = $gov->{cache}->{excavator}->{planets}->{$pid}->{$target_planet->{id}} || 0;
                    # don't excavate on occupied planets, it annoys people and they'll probable destroy the excavator anyway
                    next if $target_planet->{empire};
                    next if $target_planet->{station};
                   # next if $target_planet->{alliance};
                   # next if $target_planet->{incoming_foreign_ships};
#                    warning("sent to $target_name recently") if $last_attempt > (time - 30 * 24 * 60 * 60);
                    next if $last_attempt > (time - 30 * 24 * 60 * 60);

                    trace($target_planet->{name} . " is viable") if ($gov->{config}->{excavator}->{trace});

                    eval {
                        if( not $dry_run ){
                            $port->send_ship( $excavator_id, { body_id => $target_planet->{id} } );
                        }
                    };
                    if( my $e = Exception::Class->caught ){
                        if( $e->isa('LacunaRPCException') and $e->code == 1009 ){
                            warning("Unable to send excavator from $planet to $target_name. $e");
                            if ($e =~ /Can only be sent to asteroids and habitable planets/)
                            {
                                $gov->{cache}->{excavator}->{planets}->{$pid}->{$target_planet->{id}} = time;
                          #      next STAR;
                            }
                            next PLANET if ($e =~ /Max Excavators allowed at this Archaeology level is/);

                        #    next PLANET;
                        }
                        elsif( $e->isa('LacunaRPCException') and $e->code == 1010 ){
                            $gov->{cache}->{excavator}->{planets}->{$pid}->{$target_planet->{id}} = time;
                            warning("Sent excavator to $target_name recently") if ($gov->{config}->{excavator}->{trace});
                            $gov->write_cache;
                        }
                        else {
                            warning("Unable to send excavator[$excavator_id] from $planet to $target_name @ $star: $e");
                        }
                    }
                    else {
                        action("${dry_run} excavator[$excavator_id] sent from $planet to $target_name @ $star");
                        delete $gov->{_observatory_plugin}{ports}{$pid}{excavator2port}{$excavator_id};
                        $gov->{cache}->{excavator}->{planets}->{$pid}->{$target_planet->{id}} = time;
                        #next STAR;
                    }
                }
            }
        }

        return;
    }

    # from http://www.perlmonks.org/?node=How%20do%20I%20shuffle%20an%20array%20randomly%3F to avoid
    # adding a new dependency on Algorithm::Numerical::Shuffle

    # fisher_yates_shuffle( \@array ) : 
    # generate a random permutation of @array in place
    sub fisher_yates_shuffle {
        my $array = shift;
        my $i;
        for ($i = @$array; --$i; ) {
            my $j = int rand ($i+1);
            next if $i == $j;
            @$array[$i,$j] = @$array[$j,$i];
        }
        return @$array;
    }
}

1;
__END__
=pod

=head1 NAME

Games::Lacuna::Client::Governor::Excavator - A rudimentary plugin for Governor that will automate the targetting of excavator.

=head1 SYNOPSIS

    Add 'excavator' to the Governor configuration priorities list.

=head1 DESCRIPTION

This module examines each colony and the excavators currently available (as well as in transit)
to determine what stars the available excavators should be sent to. It is a fast-and-dirty first-fit
algorithm, intended merely do expand the observatory's scan in an every increasing radius.

This module looks for the build_excavators colony-level configuration key in the governor config.
If it's a positive number, and there are fewer than that number of excavators currently in any
state at the SpacePort of the given body, then it will attempt to build excavators to make up
the difference.

NOTE: Having ships auto-build can cause ship loss if it happens when you don't expect it, and you
push ships to a location where a probe build is later initiated.  Be careful!

=head1 DEPENDENCIES

Depends on internet access to download the static stars listing. If this is not available,
some modification of this code will be necessary. See the L</stars> subroutine for details
on how this information is used.

=head1 SEE ALSO

L<Games::Lacuna::Client>, by Steffen Mueller on which this module is dependent.

L<Games::Lacuna::Client::Governor>, by Adam Bellaire of which this module is a plugin.

L<Games::Lacuna::Client::Governor::Astronmer>, by Daniel Kimsey from which this module was derived

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Malcolm Harwood, E<lt>mjh-lacuna@liminalflux.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Malcolm Harwood

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut


