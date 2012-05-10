#!/usr/bin/perl

use strict;
use warnings;
use List::Util            ();
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

my %spies;

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $planet_name = $planets->{$planet_id};

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    
    my $buildings = $result->{buildings};

    # Find the Space Port
    my $intel_min_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Intelligence Ministry'
    } keys %$buildings;

    next unless $intel_min_id;
    
    my $intel_min = $client->building( id => $intel_min_id, type => 'Intelligence' );
    #print Dumper( $intel_min);
    
    my $spy_list = $intel_min->view_spies->{spies};
    
    $spies{$planet_name} = \@$spy_list;
}

my $name_len = List::Util::max
               map { length $_->{name} }
               map { @{ $spies{$_} } } keys %spies;

my $assn_len = List::Util::max
               map { length $_->{assigned_to}{name} }
               map { @{ $spies{$_} } } keys %spies;

foreach my $planet ( keys %spies ) {
    print "$planet\n";
    printf "%-*s  Lvl   Off/Def    %-*s        Avail  Assignment\n",
           $name_len, "Name", $assn_len, "Planet";
    print "-" x (44 + $name_len + $assn_len), "\n";
    foreach my $spy ( @{ $spies{$planet} } ) {
        printf "%-*s  %3d  %4d/%4d   %-*s  %11s  %s\n",
            $name_len, $spy->{name}, $spy->{level},
            $spy->{offense_rating}, $spy->{defense_rating},
            $assn_len, $spy->{assigned_to}{name},
            format_time( $spy->{seconds_remaining} ),
            $spy->{assignment};
    }
    print "\n";
}

sub format_time {
    my($n_secs) = @_;
    return "" if $n_secs == 0;

    my $days  = sprintf "%02d", int( $n_secs / 86400 );
    my $hours = sprintf "%02d", int( $n_secs % 86400 / 3600 );
    my $mins  = sprintf "%02d", int( $n_secs % 3600  / 60 );
    my $secs  = sprintf "%02d", $n_secs % 60;
    my $time = "$mins:$secs";
    $time = "$hours:$time" if $hours > 0;
    $time = "$days:$time" if $days > 0;
    return $time;
}

__END__

          {
            'offense_rating' => '1325',
            'politics' => '0',
            'assignment' => 'Gather Operative Intelligence',
            'name' => 'Agent Null',
            'started_assignment' => '15 11 2010 20:16:16 +0000',
            'is_available' => 0,
            'level' => '12',
            'defense_rating' => '1100',
            'mayhem' => '0',
            'assigned_to' => {
                               'body_id' => '449634',
                               'name' => 'b\'th\'n E'
                             },
            'seconds_remaining' => 17908,
            'id' => '4358',
            'theft' => '0',
            'intel' => '6',
            'available_on' => '16 11 2010 04:35:45 +0000'
          },
          },
