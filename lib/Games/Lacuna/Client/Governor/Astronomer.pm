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
        my @ships;
        my @traveling;
        my @probe_to_port;
        for my $sp ( @spaceports ){
            my $page = 0;
            while( $page <= 4 ){
                $page++;
                my $data = $sp->view_all_ships($page);
                push @ships, grep { $_->{task} eq 'Docked' and $_->{type} eq 'probe' } @{$data->{ships}};
                push @probe_to_port, map {; $_->{id} => $sp } @ships;
                push @traveling, grep { $_->{task} eq 'Travelling' and $_->{type} eq 'probe' } @{$data->{ships}};
                last if $page * $SHIPS_PER_PAGE >= $data->{number_of_ships};
            }
        }

#        ### Now find Shipyards.
#        my (@shipyards) = $gov->find_buildings('Shipyard');
#        my @yard_queue;
#        for my $yard ( @shipyards ){
#            my $page = 0;
#            while( $page <= 4 ){
#                $page++;
#                my $yard_queue = $yard->view_build_queue($page);
#                push @yard_queue, $yard_queue;
#                last if $page * $SHIPS_PER_PAGE >= $yard_queue->{number_of_ships_building};
#            }
#        }



#        $gov->{_observatory_plugin}{yards}{$pid} = {
#            yards => \@shipyards,
#            queue => \@yard_queue,
#        };
        $gov->{_observatory_plugin}{ports}{$pid} = {
            ports => \@spaceports,
            docked => \@ships,
            travel => \@traveling,
            probe2port => { @probe_to_port },
        };
        $gov->{_observatory_plugin}{stars}{$pid} = {
            observatory => $observatory,
            stars       => \@stars,
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

        if( not any {
                my $o = $gov->{_observatory_plugin}{stars}{$_}{observatory};
                $o->{max_probes} - $o->{star_count} > 0;
            } @pids
        ){
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
        while( my ($pid, $planet_xy) = each %pid_loc ){
            my ($planet_x, $planet_y) = @$planet_xy;
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
                if( $EVAL_ERROR and $EVAL_ERROR =~ m/^RPC Error \(1009\)/ ){
                    warning("Unable to send probe from $planet, Observatory is capped.");
                    next PLANET;
                }
                elsif( $EVAL_ERROR ){
                    warning("Unable to send probe[$probe_id] from $planet to $star: $EVAL_ERROR");
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

=cut


