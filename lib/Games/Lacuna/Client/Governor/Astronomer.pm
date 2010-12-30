#
#===============================================================================
#
#  DESCRIPTION:  Astronomer implements the logic to automatically explore the
#                surrounding space for an empire.
#
#===============================================================================

package Games::Lacuna::Client::Governor::Astronomer;
use strict;
use warnings qw(FATAL all);
use Carp;
use English qw(-no_match_vars);
use Data::Dumper;

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

        # There's only one.
        my ($observatory) = $gov->find_buildings('Observatory');
        if( not $observatory ){
            trace("No observatories found.");
            return;
        }

        my @stars;
        do {
            my $page = 0;
            while( $page <= 4 ){
                $page++;
                my $data = $observatory->get_probed_stars($page);
                push @stars, @{$data->{stars}};
                last if $page * $PROBES_PER_PAGE >= $data->{star_count};
            }
        };

        ### Now find Spaceports.
        my (@spaceports) = $gov->find_buildings('SpacePort');
        my @all_probes;
        my @ships;
        my @traveling;
        my @probe_to_port;
        for my $sp ( @spaceports ){
            my $page = 0;
            while( $page <= 4 ){
                $page++;
                my $data = $sp->view_all_ships($page);
                push @all_probes, grep { $_->{type} eq 'probe' } @{$data->{ships}};
                push @ships, grep { $_->{task} eq 'Docked' and $_->{type} eq 'probe' } @{$data->{ships}};
                push @probe_to_port, map {; $_->{id} => $sp } @ships;
                push @traveling, grep { $_->{task} eq 'Travelling' and $_->{type} eq 'probe' } @{$data->{ships}};
                last if $page * $SHIPS_PER_PAGE >= $data->{number_of_ships};
            }
        }

        # Build more probes if directed
        my (@shipyards) = $gov->find_buildings('Shipyard');
        my $build_probes = $config->{build_probes} || 0;
        my $probes_to_build = $build_probes - scalar @all_probes;
        trace(sprintf("Found %d probes, configured to build if less than %d found.",scalar @all_probes,$build_probes));
        while ($probes_to_build > 0) {
            eval {
                $shipyards[0]->build_ship('probe');
                action("Building new probe");
                $probes_to_build--;
            };
            if ($@) {
                $probes_to_build = 0; # Stop trying...
                warning("Unable to build probe: $@");
            }
        }

        $gov->{_observatory_plugin}{ports}{$pid} = {
            ports => \@spaceports,
            docked => \@ships,
            travel => \@traveling,
            probe2port => { @probe_to_port },
        };
        $gov->{_observatory_plugin}{stars}{$pid} = {
            observ_id   => $observatory->{building_id},
            stars       => \@stars,
        };

        if( not $class->can_observe($gov, $pid) ){
            ### Hey, maybe we should upgrade the Observatory on this planet...
            my $observatory_bldg = $gov->{client}->building(
                id      => $observatory->{building_id},
                type    => 'Observatory',
            );
            $gov->attempt_upgrade($observatory_bldg);
        }

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
                trace("Astronomer is loading cached static star map...");
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

        trace("Astronomer is downloading static star map...");
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

        my @pids = keys %{ $gov->{_observatory_plugin}{stars} };
        if( not @pids ){
            trace("No observatories found, aborting.");
            return;
        }

        my %probed_stars;
        ### Identify all probed stars.
        for my $pid ( @pids ){
            for my $star ( @{$gov->{_observatory_plugin}{stars}{$pid}{stars}} ){
                if( exists $probed_stars{$star->{name}} ){
                    warning(sprintf "Star %s has multiple probes!", $star->{name});
                    next;
                }
                $probed_stars{$star->{name}} = $star;
            }
        }

        if( not any { $class->can_observe($gov, $_); } @pids ){
            trace("All observatories are capped, aborting.");
            return;
        }

        ### Grab static star data...
        my %stars = %{ $class->stars($gov) || {} };
        if( not scalar keys %stars ){
            warning("Stars map is empty, this is *highly* unlikely.");
            return;
        }

        ### Find all stars that are not probed.
        my %valid_target_stars =
            map  {; $_ => $stars{$_} }
            grep { not exists $probed_stars{$_} }
            keys %stars;

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
            $distances_by_planet{$pid} = [
                sort {
                   $planet_distances{$pid}{$a} <=> $planet_distances{$pid}{$b}
                } keys %{ $planet_distances{$pid} }
            ];
        }

        ### Launch ze Probes!
        $class->search_and_scan($gov, \%planet_distances, \%distances_by_planet);

        return;
    }

    sub can_observe {
        my $class   = shift;
        my $gov     = shift;
        my $pid     = shift;
        my $oid = $gov->{_observatory_plugin}{stars}{$pid}{observ_id};
        my $o   = $gov->building_details($pid, $oid);
        my $max_probes      = $o->{level} * $PROBES_PER_LVL;
        my $active_probes   = scalar @{$gov->{_observatory_plugin}{stars}{$pid}{stars}};
        return $max_probes - $active_probes > 0;
    }

    sub search_and_scan {
        my $class = shift;
        my $gov   = shift;
        my $planet_distances    = shift;
        my $distances_by_planet = shift;
        my $stars = $class->stars($gov);

        ### Denote probes currently in transit.
        my %traveling_probes = map {
            my $travel = $gov->{_observatory_plugin}{ports}{$_}{travel};
            # If there are multiple probes to one dest. Don't care at this point.
            # We already informed the user there are duplicates. Let the Humans figure
            # out how best to resolve that.
            map {; $_->{to}{name} => $_; } @$travel;
        } keys %{$gov->{_observatory_plugin}{ports}};

        ### How many probes are available for us to send?
        my %probe_cnt;
        my %docked_probes = map {
            my $docked = $gov->{_observatory_plugin}{ports}{$_}{docked};
            $probe_cnt{$_}+= scalar @$docked;
            $_ => $docked;
        } keys %{$gov->{_observatory_plugin}{ports}};

        ### Select our targets. Naively.
        my %closest_launch;
        my %probe_from_planet;
        PLANET:
        for my $pid ( keys %docked_probes ){
            my $closest_stars = $distances_by_planet->{$pid};
            STAR:
            for my $star ( @{$closest_stars} ){
                next PLANET if not $probe_cnt{$pid};
                next STAR if $traveling_probes{$star} or $closest_launch{$star};
                $closest_launch{$star} = $pid;
                push @{$probe_from_planet{$pid}}, $star;
                $probe_cnt{$pid}--;
            }
        }

        my $dry_run = $gov->{config}{dry_run} ? "[DRYRUN]: " : '';
        ### Launch.
        PLANET:
        while( my ($pid, $star_targets) = each %probe_from_planet ){
            my $planet = $gov->{status}{$pid}{name};
            STAR:
            for my $star ( @$star_targets ){
                my ($probe_id) = keys %{$gov->{_observatory_plugin}{ports}{$pid}{probe2port}};
                last STAR if not $probe_id;
                my $port  = delete $gov->{_observatory_plugin}{ports}{$pid}{probe2port}{$probe_id};

                eval {
                    if( not $dry_run ){
                        $port->send_ship( $probe_id, { star_name => $star } );
                    }
                };
                if( my $e = Exception::Class->caught ){
                    if( $e->isa('LacunaRPCException') and $e->code == 1009 ){
                        warning("Unable to send probe from $planet, Observatory is capped.");
                        next PLANET;
                    }
                    else {
                        warning("Unable to send probe[$probe_id] from $planet to $star: $e");
                    }
                }
                else {
                    action("${dry_run}Probe[$probe_id] sent from $planet to $star");
                }
            }
        }

        return;
    }

}

1;
__END__
=pod

=head1 NAME

Games::Lacuna::Client::Governor::Astronomer - A rudimentary plugin for Governor that will automate the targetting of probes.

=head1 SYNOPSIS

    Add 'astronomer' to the Governor configuration priorities list.

=head1 DESCRIPTION

This module examines each colony and the probes currently available (as well as in transit)
to determine what stars the available probes should be sent to. It is a fast-and-dirty first-fit
algorithm, intended merely do expand the observatory's scan in an every increasing radius.

This module looks for the build_probes colony-level configuration key in the governor config.
If it's a positive number, and there are fewer than that number of probes currently in any
state at the SpacePort of the given body, then it will attempt to build probes to make up
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

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Daniel Kimsey, E<lt>dekimsey@ufl.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut


