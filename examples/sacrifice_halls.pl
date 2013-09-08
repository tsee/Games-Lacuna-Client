#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util qw(first shuffle);
use Data::Dumper;
$Data::Dumper::Maxdepth = 1;

use Getopt::Long;
use Games::Lacuna::Client;

my %opts;
GetOptions(\%opts,
    # General options
    'h|help',
    'q|quiet',
    'v|verbose',
    'config=s',
    'planet=s@',
    'dry-run|dry',
    'max=i',
    'delay=s',
) or usage();

usage() if $opts{h};

my %do_planets;
if ($opts{planet}) {
    %do_planets = map { normalize_planet($_) => 1 } @{$opts{planet}};
}

my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "$FindBin::Bin/../lacuna.yml",
);

# need a Halls object to do any construction
my $halls = $glc->building(type => 'HallsOfVrbansk');

my $empire = $glc->empire->get_status->{empire};
# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
for my $planet_name (keys %planets) {
    if (keys %do_planets) {
        next unless $do_planets{normalize_planet($planet_name)};
    }

    verbose("Inspecting $planet_name\n");

    # Load planet data
    my $planet    = $glc->body(id => $planets{$planet_name});
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    my $hall = find_building($buildings, "Halls of Vrbansk");
    verbose("No Halls on $planet_name\n") unless $hall;
    next unless $hall;


    my %upgrades = 
    (
        "Geo Thermal Vent" => 25,
        "Natural Spring" => 25,
        "Volcano" => 25,
        "Lapis Forest" => 20,
        "Amalgus Meadow" => 20,
        "Algae Pond" => 20,
        "Malcud Field" => 20,
        "Denton Brambles" => 21,
        "Beeldeban Nest" => 21,
        "Interdimensional Rift" => 26,
#        "Kalavian Ruins" => 30,
#        "Pantheon of Hagness" => 9,
        "Ravine" => 15,
    );

    my %upgrade_buildings;
    foreach my $name (keys %upgrades)
    {
        my $upgradable;
        eval 
        {
            $hall = find_building($buildings, "Halls of Vrbansk");
            last unless $hall;
            $upgradable = $hall->get_upgradable_buildings();
        };
        if ($@)
        {
            warn "can't find hall on $name: " . $@;
            last;
        }

        my %upgradable = map { $_->{efficiency} ||= 100; $_->{id} => $_ } @{$upgradable->{buildings}};
        my $building = find_building(\%upgradable, $name);
        if (defined $building)
        {
        if ($building->{level} < $upgrades{$name})
        {
            eval 
            {
                $hall->sacrifice_to_upgrade($building->{building_id});
            };
            if ($@)
            {
                warn "upgrade of $name failed: " . $@;
                next;
            }
            output("upgraded $name on $planet_name from $building->{level}\n");
            $result    = $planet->get_buildings;
            $buildings = $result->{buildings};
        }
        else
        {
            output("  $name on $planet_name at limit: $building->{level}\n");
            }
        }
    }

    my $forge = find_building($buildings, "The Dillon Forge");
    if ($forge)
    {
        eval
        {
            $forge->split_plan ( "Permanent::CrashedShipSite", 1, 0 );
        };
            if ($@)
            {
                warn "split failed: " . $@;
            }
    }
}

verbose("$glc->{total_calls} api calls made.\n");
verbose("You have made $glc->{rpc_count} calls today\n");
verbose(Dumper $glc->{call_stats});
undef $glc;

exit 0;

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub find_building {
    my ($buildings, $name) = @_;

    my $id = first {
        $buildings->{$_}->{name} eq $name
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not $id;
    my $type = Games::Lacuna::Client::Buildings::type_from_url($buildings->{$id}->{'url'});

    my $building  = $glc->building(
        id   => $id,
        type => $type,
        level => $buildings->{$id}->{level},
    );

    return $building;
}

sub usage {
    diag(<<END);
Usage: $0 [options]

Options:
  --verbose              - Output extra information.
  --quiet                - Print no output except for errors.
  --config <file>        - Specify a GLC config file, normally lacuna.yml.
  --planet <name>        - Specify a planet to process.  This option can be
                           passed multiple times to indicate several planets.
                           If this is not specified, all relevant colonies will
                           be inspected.
  --dry-run              - Don't actually take any action, just report status and
                           what actions would have taken place.
  --max <n>              - Build at most <n> Halls, default is 1
  --delay <n>            - Sleep for <n> seconds between each build
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
