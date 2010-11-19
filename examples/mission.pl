#!/usr/bin/perl 
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Games::Lacuna::Client;
use Games::Lacuna::Client::PrettyPrint qw(warning action);

$| = 1;

my $client_config   = '/path/to/your/config';
my $client = Games::Lacuna::Client->new( cfg_file => $client_config );
my $planet;
my $use_color;
my $show_help;
my @skip;
my @complete;

GetOptions(
    'help'       => \$show_help,
    'color'      => \$use_color,
    'planet=s'   => \$planet,
    'skip=n'     => \@skip,
    'complete=n' => \@complete,
);

if ($show_help) {
    print << 'END_USAGE';
Usage: perl mission.pl [options]

This script lets you view, complete, or skip missions in your mission command.  If
--complete or --skip are not specified, a listing of available missions is displayed.
--skip and --complete may be specified more than once, and mixed with one another.

Options:
 --help            This help screen
 --color           Show ANSI color
 --planet          The name of the planet to use when obtaining the Mission Command.
                   If not specified, the first mission command found is used.
 --skip [id]       Skip the mission specified by [id]
 --complete [id]   Complete the mission specified by [id]

END_USAGE
    exit;
}

$Games::Lacuna::Client::PrettyPrint::ansi_color = $use_color;
my $data = $client->empire->view_species_stats();
my $mc_id;
my $found_planet;

for my $pid (keys %{$data->{status}->{empire}->{planets}}) {
    next if (defined $planet and $planet ne '' and $data->{status}->{empire}->{planets}->{$pid} ne $planet);
    $found_planet = $data->{status}->{empire}->{planets}->{$pid};
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    ($mc_id) = grep { $buildings->{$_}->{url} eq '/missioncommand' } keys %$buildings;
    last if ($mc_id);
}

if (not defined $mc_id) {
    die "Unable to find the Mission Command on planet '$planet'.";
}


my $mc = $client->building( id => $mc_id, type => 'MissionCommand');

for my $skip (@skip) {
    eval {
        $mc->skip_mission($skip);
    };
    if ($@) {
        warning("Unable to skip mission: $@");
    } else {
        action("Mission $skip skipped.");
    }
}

for my $complete (@complete) {
    eval {
        $mc->complete_mission($complete);
    };
    if ($@) {
        warning("Unable to complete mission: $@");
    } else {
        action("Mission $complete completed.");
    }
}

exit if (scalar @complete or scalar @skip);

Games::Lacuna::Client::PrettyPrint::mission_list($found_planet,@{$mc->get_missions->{missions}});
