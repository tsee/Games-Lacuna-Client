#!/usr/bin/env perl
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

  my %opts = (
    max => 0,
  );
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
    cfg_file => $opts{config} || "lacuna.yml",
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
  my (%glyphs_h, %archmins, %plan_count);
  for my $planet_name (sort keys %planets) {
    if (keys %do_planets) {
        next unless $do_planets{normalize_planet($planet_name)};
    }

    my %planet_buildings;

    # Load planet data
    my $planet    = $glc->body(id => $planets{$planet_name});
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    # Find the Archaeology Ministry
    my $arch_id = first {
        $buildings->{$_}->{name} eq 'Archaeology Ministry'
    } keys %$buildings;

    next unless $arch_id;
    my $arch   = $glc->building(id => $arch_id, type => 'Archaeology');
    $archmins{$planet_name} = $arch;
    my $glyphs_aref = $arch->get_glyph_summary->{glyphs};

    for my $glyph (@$glyphs_aref) {
      $glyph->{quantity}-- unless $opts{'use-last'};
      verbose( "Found $glyph->{quantity} of $glyph->{name} on $planet_name.\n");
      if ($glyph->{quantity}) {
        $glyphs_h{$planet_name}->{$glyph->{name}} = $glyph->{quantity};
      }
    }
  }

  my %possible_builds;
  my $all_possible = 0;
  for my $i (0..$#recipes) {
    next if $opts{type} and not $build_types{$i};
    my $type = $i + 1;

    # Determine how many of each we're able to build
    PLANET:
    for my $planet (sort keys %glyphs_h) {
      my $can_build_here = min(
        map { $glyphs_h{$planet}{$_} ? $glyphs_h{$planet}{$_} : 0 } @{$recipes[$i]}
      );

      output("$planet can build $can_build_here Halls #$type\n")
        if $can_build_here;
      if ($opts{max}) {
        if ($all_possible + $can_build_here > $opts{max}) {
          $can_build_here = $opts{max} - $all_possible;
        }
      }

      if ($can_build_here) {
        push @{$possible_builds{$type}}, {
             planet => $planet,
             arch   => $archmins{$planet},
             type   => $type,
             recipe => $recipes[$i],
             glyphs => $can_build_here,
        };
        $all_possible += $can_build_here;
      }
      last if ($opts{max} && $all_possible >= $opts{max});
    }
  }

# Do builds
  verbose("Planning to build $all_possible Halls\n");

  my $total_built;
  for my $type ( sort keys %possible_builds) {
    for my $build (sort {$a->{planet} cmp $b->{planet}} @{$possible_builds{$type}}) {
      if ($opts{'dry-run'}) {
        output("Would have built $build->{glyphs} Halls #$build->{type} on $build->{planet}\n");
      }
      else {
        while ($build->{glyphs} > 0) {
          my $num_bld = 0;
          if ($build->{glyphs} > 5000) {
            $num_bld = 5000;
            $build->{glyphs} -= 5000;
          }
          else {
            $num_bld = $build->{glyphs};
            $build->{glyphs} = 0;
          }
          output("Building a $num_bld Halls #$build->{type} on $build->{planet}\n");
          my $ok = eval {
            $build->{arch}->assemble_glyphs($build->{recipe}, $num_bld);
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
          $plan_count{$build->{planet}} += $num_bld;
        }
      }
    }
  }
  unless ($opts{'dry-run'}) {
    for my $pname ( sort keys %plan_count) {
      output ($plan_count{"$pname"}." Halls built on $pname.\n");
    }
  }

  output("$glc->{total_calls} api calls made.\n");
  output("You have made $glc->{rpc_count} calls today\n");
exit;

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
