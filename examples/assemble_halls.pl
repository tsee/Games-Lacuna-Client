#!/usr/bin/perl
#
# Assemble Halls of Vrbansk recipes, wherever they can be assembled
#

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use Data::Dumper;
use List::Util qw(first min max sum);

use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;

my %opts;
GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'q|quiet',
    'config=s',
    'planet=s@',
    'max=i',
    'use-last',
    'dry-run',
    'type=s@',
);

usage() if $opts{h};

my %do_planets;
if ($opts{planet}) {
    %do_planets = map { normalize_planet($_) => 1 } @{$opts{planet}};
}

my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "$FindBin::Bin/../lacuna.yml",
    rpc_sleep => 1,
);

my $empire = $glc->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};

my @recipes = (
    [qw/ goethite  halite      gypsum        trona     /],
    [qw/ gold      anthracite  uraninite     bauxite   /],
    [qw/ kerogen   methane     sulfur        zircon    /],
    [qw/ monazite  fluorite    beryl         magnetite /],
    [qw/ rutile    chromite    chalcopyrite  galena    /],
);

my %build_types;
my %normalized_types = (
    (map { $_ => $_ - 1 } 1..5),
    a => 0,
    b => 1,
    c => 2,
    d => 3,
    e => 4,
);
if ($opts{type}) {
    # normalize type
    for (@{$opts{type}}) {
        $build_types{lc($normalized_types{$_})} = 1
            if defined lc($normalized_types{$_});
    }
}

# Scan each planet
my (%glyphs, %archmins, %plan_count);
for my $planet_name (sort keys %planets) {
    if (keys %do_planets) {
        next unless $do_planets{normalize_planet($planet_name)};
    }

    my %planet_buildings;

    # Load planet data
    my $planet    = $glc->body(id => $planets{$planet_name});
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    # Find the PCC
    my $pcc_id = first {
        $buildings->{$_}->{name} eq 'Planetary Command Center'
    } keys %$buildings;

    unless ($pcc_id) {
        verbose("$planet_name has no PCC (possibly a Space Station), skipping\n");
        next;
    }

    my $pcc = $glc->building(id => $pcc_id, type => 'PlanetaryCommand');
    my $plans = $pcc->view_plans;
    $plan_count{$planet_name} = scalar @{$plans->{plans}};

    # Find the Archaeology Ministry
    my $arch_id = first {
        $buildings->{$_}->{name} eq 'Archaeology Ministry'
    } keys %$buildings;

    next unless $arch_id;
    my $arch   = $glc->building(id => $arch_id, type => 'Archaeology');
    $archmins{$planet_name} = $arch;
    my $glyphs = $arch->get_glyphs->{glyphs};

    for my $glyph (@$glyphs) {
        push @{$glyphs{$planet_name}{$glyph->{type}}}, $glyph->{id};
    }
}

my (%possible_builds, $all_possible);
for my $i (0..$#recipes) {
    next if $opts{type} and not $build_types{$i};
    my $type = $i + 1;

    # Determine how many of each we're able to build
    PLANET:
    for my $planet (keys %glyphs) {
        my $can_build_here = min(
            map { $glyphs{$planet}{$_} ? scalar @{$glyphs{$planet}{$_}}: 0 } @{$recipes[$i]}
        );

        output("$planet can build $can_build_here Halls #$type\n")
            if $can_build_here;

        for my $j (0 .. $can_build_here - 1) {
            push @{$possible_builds{$type}}, {
                planet => $planet,
                arch   => $archmins{$planet},
                type   => $type,
                glyphs => [
                    map { $glyphs{$planet}{$_}[$j] } @{$recipes[$i]}
                ],
            };
            $all_possible++;
        }
    }
}

# Drop one from each type unless we're allowed to use all glyphs
unless ($opts{'use-last'}) {
    verbose("Not using last, dropping one of each type\n");
    pop @{$possible_builds{$_}} for keys %possible_builds;
}

# Do builds
my $total = sum(map { scalar @{$possible_builds{$_}} } keys %possible_builds) || 0;
my $need = $opts{max} ? min($opts{max}, $total) : $total;
verbose("Planning to build $need Halls\n");

# First grab approximately the right percentage from each set
my @builds;
for my $type (keys %possible_builds) {
    my $have = @{$possible_builds{$type}};
    my $grab = $total ? int(($have / $total) * $need) : 0;
    verbose("Grabbing $grab of type $type\n");
    for (1..$grab) {
        push @builds, pop @{$possible_builds{$type}};
    }
}

while (@builds < $need) {
    my ($type) = sort { @{$possible_builds{$b}} <=> @{$possible_builds{$a}}} keys %possible_builds;
    verbose("Not enough (" . scalar(@builds) . " of $need), taking another $type\n");
    push @builds, pop @{$possible_builds{$type}};
}

for my $build (sort { $a->{type} cmp $b->{type} } @builds) {
    if ($opts{'dry-run'}) {
#        output("Would have built a Halls #$build->{type} on $build->{planet}\n");
    } else {
        output("Building a Halls #$build->{type} on $build->{planet}\n");
        my $ok = eval {
          $build->{arch}->assemble_glyphs($build->{glyphs});
        };
        unless ($ok) {
          my $error = $@;
          if ($error =~ /1010/) {
            print $error," taking a minute off.\n";
            sleep(60);
          }
          else {
            die "$error\n";
          }
        }
    }
    $plan_count{$build->{planet}}++;
}

if (@builds) {
    if ($all_possible > $need) {
        my $diff = $all_possible - $need;
        output("$diff more Halls are possible, specify --use-last if you want to build all possible Halls\n");
    }
} else {
    if ($total) {
        output("No Halls built ($all_possible possible), specify --use-last if you want to build all possible Halls\n");
    } else {
        output("Not enough glyphs to build any Halls recipes, sorry\n");
    }
}

output("$glc->{total_calls} api calls made.\n");
output("You have made $glc->{rpc_count} calls today\n");

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub usage {
    print STDERR <<END;
Usage: $0 [options]

This will assemble Halls of Vrbansk recipes wherever there are enough
glyphs in the same location to do so.  By default, it will not use
the last of any particular type of glyph.

Options:

  --verbose       - Print more output
  --quiet         - Only output errors
  --config <file> - GLC config, defaults to lacuna.yml
  --max <n>       - Build at most <n> Halls
  --planet <name> - Build only on the specified planet(s)
  --use-last      - Use the last of any glyph if necessary
  --dry-run       - Print what would have been built, but don't do it
  --type <type>   - Specify a particular recipe to build (1-5 or A-E)
END

    exit 1;
}
