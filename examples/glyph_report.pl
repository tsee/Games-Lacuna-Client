#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use YAML;
use YAML::Dumper;
use Getopt::Long qw(GetOptions);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);
my $recipe_yml = 'glyph_recipes.yml';

GetOptions{
  'g=s' => \$recipe_yml,
};

#Load recipe file
my $recipes = YAML::LoadFile($recipe_yml);

my %glyph_names = (
"anthracite" => 0,
"bauxite" => 0,
"beryl" => 0,
"chalcopyrite" => 0,
"chromite" => 0,
"fluorite" => 0,
"galena" => 0,
"goethite" => 0,
"gold" => 0,
"gypsum" => 0,
"halite" => 0,
"kerogen" => 0,
"magnetite" => 0,
"methane" => 0,
"monazite" => 0,
"rutile" => 0,
"sulfur" => 0,
"trona" => 0,
"uraninite" => 0,
"zircon" => 0,
"unknown" => 0, # For recipes we know exist, but don't know what goes in them
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
foreach my $name ( sort keys %planets ) {

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the Archaeology Ministry
    my $arch_id = first {
            $buildings->{$_}->{name} eq 'Archaeology Ministry'
    } keys %$buildings;
    
    next unless $arch_id;
    my $arch   = $client->building( id => $arch_id, type => 'Archaeology' );
    my $glyphs = $arch->get_glyphs->{glyphs};
    
    next if !@$glyphs;
    
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    @$glyphs = sort { $a->{type} cmp $b->{type} } @$glyphs;
    
    for my $glyph (@$glyphs) {
        printf "%s\n", ucfirst( $glyph->{type} );
        $glyph_names{$glyph->{type}}++;
    }
    
    print "\n";
}

print "\nPossible Recipes:\n";
foreach my $recipe (sort @$recipes) {
  my $good = 1;
  foreach my $ingredient (@{$recipe->{types}}) {
    unless (defined($glyph_names{$ingredient})) {
      print "Define: $ingredient\n";
      next;
    }
    $good = 0 if ($glyph_names{$ingredient} == 0);
  }
  if ($good) {
    print $recipe->{name}, ": ", join(" ", @{$recipe->{types}}), "\n";
  }
}
