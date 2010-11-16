#!/usr/bin/perl
use strict;
use warnings;
use Games::Lacuna::Client;
use YAML;
use YAML::Dumper;
use Getopt::Long qw(GetOptions);

binmode STDOUT, ":utf8";

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
);

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
                      keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'

my @glyphs;

foreach my $planet (values %planets_by_name) {
  my %buildings = %{ $planet->get_buildings->{buildings} };

  my @b = grep {$buildings{$_}{name} eq 'Archaeology Ministry'}
                  keys %buildings;
  my @amin;
  push @amin, map  { $client->building(type => 'Archaeology', id => $_) } @b;

  for my $bld (@amin) {
    my $glyph = $bld->get_glyphs();

    foreach my $gly ( @{$glyph->{glyphs}} ) {
      $gly->{planet} = $glyph->{status}->{body}->{name};
    }
    push @glyphs, @{$glyph->{glyphs}};
  }
}


printf "%s,%s,%s\n", "Planet", "Glyph","ID";
foreach my $glyph (sort byglyphsort @glyphs) {
  printf "%s,%s,%d\n",
         $glyph->{planet}, $glyph->{type}, $glyph->{id};
  $glyph_names{$glyph->{type}}++;
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
    print $recipe->{name}, ":", join(" ", @{$recipe->{types}}), "\n";
  }
}


sub byglyphsort {
   $a->{planet} cmp $b->{planet} ||
    $a->{type} cmp $b->{type} ||
    $a->{id} <=> $b->{id}; 
    
}
