#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util qw(first shuffle);
use Data::Dumper;

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

    my $pcc = find_pcc($buildings);
    next unless $pcc;

    my $plans = $pcc->view_plans->{plans};
    unless (@$plans) {
        verbose("No plans on $planet_name\n");
        next;
    }

    my @halls = grep { $_->{name} eq 'Halls of Vrbansk' } @$plans;
    unless (@halls) {
        verbose("No Halls on $planet_name\n");
        next;
    }

    # initialize plots
    my %plots;
    for my $x (-5..5) {
        for my $y (-5..5) {
            $plots{"$x:$y"} = 1;
        }
    }
    for (keys %$buildings) {
        delete $plots{"$buildings->{$_}{x}:$buildings->{$_}{y}"};
    }

    my $max = $opts{max} || 1;
    for (1..$max) {
        last unless keys %plots;
        last unless @halls;
        my ($plot) = shuffle(keys %plots);
        my ($x, $y) = $plot =~ /([\d-]+):([\d-]+)/;
        delete $plots{$plot};
        pop @halls;
        if ($opts{'dry-run'}) {
            output("Would have placed Halls at $x, $y on $planet_name\n");
        } else {
            output("Placing Halls at $x, $y on $planet_name\n");
            $halls->build($planets{$planet_name}, $x, $y);
        }

        sleep $opts{delay} if $opts{delay};
    }
}

output("$glc->{total_calls} api calls made.\n");
output("You have made $glc->{rpc_count} calls today\n");
output(Dumper $glc->{call_stats});
undef $glc;

exit 0;

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub find_pcc {
    my ($buildings) = @_;

    # Find the PCC
    my $pcc_id = first {
        $buildings->{$_}->{name} eq 'Planetary Command Center'
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    return if not $pcc_id;

    my $building  = $glc->building(
        id   => $pcc_id,
        type => 'PlanetaryCommand',
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
