#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw( first sum ));
use List::MoreUtils       qw( none );
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

if ( $^O !~ /MSWin32/) {
    $Games::Lacuna::Client::PrettyPrint::ansi_color = 1;
}

my @planets;
my $opt_glyph_type = {};
GetOptions(
    'planet=s@' => \@planets,
    'c|color!'  => \$Games::Lacuna::Client::PrettyPrint::ansi_color,
    't|type=s'  => sub { $opt_glyph_type->{$_[1]} = 1; },
    'f|functional!' => sub { $opt_glyph_type->{'Functional Recipes'} = 1; },
    'd|decorative!' => sub { $opt_glyph_type->{'Decorative Recipes'} = 1; },
);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file  => $cfg_file,
    rpc_sleep => 2,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Scan each planet
my %all_glyphs;
foreach my $name ( sort keys %planets ) {

    next if @planets && none { lc $name eq lc $_ } @planets;

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};

    my $buildings = $result->{buildings};

    my $glyphs = get_glyphs( $client, $buildings );

    next if !@$glyphs;

    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";

    @$glyphs = sort { $a->{type} cmp $b->{type} } @$glyphs;

    my %glyphs;

    for my $glyph (@$glyphs) {
        $glyphs{$glyph->{type}}++;

        $all_glyphs{$glyph->{type}} = 0 if not $all_glyphs{$glyph->{type}};
        $all_glyphs{$glyph->{type}}++;
    }

    map {
        printf "%s (%d)\n", ucfirst( $_ ), $glyphs{$_};
    } sort keys %glyphs;

    printf "\t(%d glyphs)\n", sum values %glyphs;

    print "\n";
}

creation_summary(%all_glyphs);

exit;


sub get_glyphs {
    my ( $client, $buildings ) = @_;

    my $id;
    my $type;

    # Find the Archaeology Ministry
    my $arch_id = first {
            $buildings->{$_}->{url} eq '/archaeology'
    } keys %$buildings;

    if ( $arch_id ) {
        $id   = $arch_id;
        $type = 'Archaeology';
    }
    else {
        my $trade_id = first {
                $buildings->{$_}->{url} eq '/trade'
        } keys %$buildings;

        if ( $trade_id ) {
            $id   = $trade_id;
            $type = 'Trade';
        }
    }

    return [] if !$id;

    my $building = $client->building( id => $id, type => $type );

    return $building->get_glyphs->{glyphs};
}

# Print out a pretty table of what we can make.
sub creation_summary {
    my %contents = @_;
    use Data::Dumper;
    use List::Util qw(reduce);
    use YAML::Any qw(LoadFile);
    my $yml = LoadFile( \*DATA );
    my %ready;
    my %remaining;
    my @keys = ( keys %$yml );
    @keys = grep { $opt_glyph_type->{$_} } @keys if keys %$opt_glyph_type;

    for my $title ( @keys )
    {
        print _c_('bold white'), "\n$title\n", "=" x length $title, "\n", _c_('reset');
        printf qq{%-30s%-10s%s\n}, "Building", "Missing", "Glyph Combine Order";
        print q{-} x 80, "\n";
        my %recipes = %{$yml->{$title}};
        for my $glyph ( keys %recipes ){
            my ($order, $quantity) = @{$recipes{$glyph}}{qw(order quantity)};
            my $missing = reduce {
                #print "\t$glyph requires $b [", $quantity->{$b}, ",", $contents{$b} || 0, "]\n";
                my $m = $quantity->{$b} - ($contents{$b} || 0);
                $m = $m < 0 ? 0 : $m;
                $remaining{$glyph}{$b} = $m;
                $a + $m;
            } 0, keys %$quantity;
            $ready{$glyph} = $missing;
        }
        my @available_glyphs = sort { $ready{$a} <=> $ready{$b} || $a cmp $b } keys %recipes;
        my $lvl;
        for my $glyph ( sort @available_glyphs ){
            my $c = {
                0   => _c_('green'),
                1   => _c_('yellow'),
                2   => _c_('red'),
                3   => _c_('red'),
                4   => _c_('red'),
            }->{$ready{$glyph}};

            printf qq{%s%-30s%s%-10d}, $c, $glyph, _c_('reset'), $ready{$glyph};
            # Print build order.
            my @out;
            for my $ordered ( @{$recipes{$glyph}{order}} ){
                my $segment = !$remaining{$glyph}{$ordered} ? _c_('green') : _c_('red');
                my $no_color_ask = '';
                if(not $Games::Lacuna::Client::PrettyPrint::ansi_color) {
                    $no_color_ask = $remaining{$glyph}{$ordered} ? '*' : '';
                }
                $segment .= sprintf qq{%-15s}, $ordered . ($no_color_ask );
                $segment .= _c_('reset');
                push @out, $segment;
            }
            print join q{}, @out, "\n";
        }
    }
}

sub _c_ {
    use Games::Lacuna::Client::PrettyPrint;
    Games::Lacuna::Client::PrettyPrint::_c_(@_);
}

__DATA__
%YAML 1.1
---
Decorative Recipes:
  Beach 1 (Land E):
    order:
        - gypsum
    quantity:
      gypsum: 1
  Beach 10 (Sea SW):
    order:
        - gypsum
        - methane
    quantity:
      gypsum: 1
      methane: 1
  Beach 11 (Land S):
    order:
        - gypsum
        - chromite
    quantity:
      chromite: 1
      gypsum: 1
  Beach 12 (Land W?):
    order:
      - gypsum
      - goethite
    quantity:
      goethite: 1
      gypsum: 1
  Beach 13 (Land W?):
    order:
      - gypsum
      - galena
    quantity:
      galena: 1
      gypsum: 1
  Beach 2 (Land SW):
    order:
      - gypsum
      - gypsum
    quantity:
      gypsum: 2
  Beach 3 (Land SE):
    order:
      - gypsum
      - magnetite
    quantity:
      gypsum: 1
      magnetite: 1
  Beach 4 (Sea NW):
    order:
      - gypsum
      - uraninite
    quantity:
      gypsum: 1
      uraninite: 1
  Beach 5 (Land N):
    order:
      - gypsum
      - halite
    quantity:
      gypsum: 1
      halite: 1
  Beach 6 (Land NW):
    order:
      - gypsum
      - rutile
    quantity:
      gypsum: 1
      rutile: 1
  Beach 7 (Land NE):
    order:
      - gypsum
      - chalcopyrite
    quantity:
      chalcopyrite: 1
      gypsum: 1
  Beach 8 (Sea SE):
    order:
      - gypsum
      - sulfur
    quantity:
      gypsum: 1
      sulfur: 1
  Beach 9 (Sea Only):
    order:
      - gypsum
      - anthracite
    quantity:
      anthracite: 1
      gypsum: 1
  Crater:
    order:
      - rutile
    quantity:
      rutile: 1
  Grove of Trees:
    order:
      - methane
    quantity:
      methane: 1
  Lagoon:
    order:
      - chalcopyrite
    quantity:
      chalcopyrite: 1
  Lake:
    order:
      - goethite
    quantity:
      goethite: 1
  Patch of Sand:
    order:
      - bauxite
    quantity:
      bauxite: 1
  Rocky Outcropping:
    order:
      - trona
    quantity:
      trona: 1
Functional Recipes:
  Algae Pond:
    order:
      - uraninite
      - methane
    quantity:
      methane: 1
      uraninite: 1
  Amalgus Meadow:
    order:
      - beryl
      - trona
    quantity:
      beryl: 1
      trona: 1
  Beeldeban Nest:
    order:
      - anthracite
      - trona
      - kerogen
    quantity:
      anthracite: 1
      trona: 1
      kerogen: 1
  Citadel of Knope:
    order:
      - beryl
      - sulfur
      - monazite
      - galena
    quantity:
      beryl: 1
      galena: 1
      monazite: 1
      sulfur: 1
  Crashed Ship Site:
    order:
      - monazite
      - trona
      - gold
      - bauxite
    quantity:
      bauxite: 1
      gold: 1
      monazite: 1
      trona: 1
  Denton Brambles:
    order:
      - rutile
      - goethite
    quantity:
      rutile: 1
      goethite: 1
  Gas Giant Settlement Platform:
    order:
      - sulfur
      - methane
      - galena
      - anthracite
    quantity:
      anthracite: 1
      galena: 1
      methane: 1
      sulfur: 1
  Geo Thermal Vent:
    order:
      - chalcopyrite
      - sulfur
    quantity:
      chalcopyrite: 1
      sulfur: 1
  Gratch's Gauntlet:
    order:
      - chromite
      - bauxite
      - gold
      - kerogen
    quantity:
      chromite: 1
      bauxite: 1
      gold: 1
      kerogen: 1
  Halls of Vrbansk (A):
    order:
      - goethite
      - halite
      - gypsum
      - trona
    quantity:
      goethite: 1
      halite: 1
      gypsum: 1
      trona: 1
  Halls of Vrbansk (B):
    order:
      - gold
      - anthracite
      - uraninite
      - bauxite
    quantity:
      gold: 1
      anthracite: 1
      uraninite: 1
      bauxite: 1
  Halls of Vrbansk (C):
    order:
      - kerogen
      - methane
      - sulfur
      - zircon
    quantity:
      kerogen: 1
      methane: 1
      sulfur: 1
      zircon: 1
  Halls of Vrbansk (D):
    order:
      - monazite
      - fluorite
      - beryl
      - magnetite
    quantity:
      monazite: 1
      fluorite: 1
      beryl: 1
      magnetite: 1
  Halls of Vrbasnk (E):
    order:
      - rutile
      - chromite
      - chalcopyrite
      - galena
    quantity:
      rutile: 1
      chromite: 1
      chalcopyrite: 1
      galena: 1
  Interdimensional Rift:
    order:
      - methane
      - zircon
      - fluorite
    quantity:
      fluorite: 1
      methane: 1
      zircon: 1
  Kalavian Ruins:
    order:
      - galena
      - gold
    quantity:
      galena: 1
      gold: 1
  Lapis Forest:
    order:
      - halite
      - anthracite
    quantity:
      anthracite: 1
      halite: 1
  Malcud Field:
    order:
      - fluorite
      - kerogen
    quantity:
      fluorite: 1
      kerogen: 1
  Natural Spring:
    order:
      - magnetite
      - halite
    quantity:
      halite: 1
      magnetite: 1
  Oracle of Anid:
    order:
      - gold
      - uraninite
      - bauxite
      - goethite
    quantity:
      bauxite: 1
      goethite: 1
      gold: 1
      uraninite: 1
  Pantheon of Hagness:
    order:
      - gypsum
      - trona
      - beryl
      - anthracite
    quantity:
      anthracite: 1
      beryl: 1
      gypsum: 1
      trona: 1
  Ravine:
    order:
      - zircon
      - methane
      - galena
      - fluorite
    quantity:
      fluorite: 1
      galena: 1
      methane: 1
      zircon: 1
  Temple of the Drajilites:
    order:
      - kerogen
      - rutile
      - chromite
      - chalcopyrite
    quantity:
      chalcopyrite: 1
      chromite: 1
      kerogen: 1
      rutile: 1
  Terraforming Platform:
    order:
      - methane
      - zircon
      - magnetite
      - beryl
    quantity:
      beryl: 1
      magnetite: 1
      methane: 1
      zircon: 1
  Volcano:
    order:
      - magnetite
      - uraninite
    quantity:
      magnetite: 1
      uraninite: 1
...
