#!/usr/bin/perl
use strict;
use warnings;
use YAML qw'LoadFile';
use File::Spec::Functions qw' abs2rel catfile ';
use Template;

use FindBin;
use lib "${FindBin::Bin}";
use LoadBuilding ();

my $input          = "${FindBin::Bin}/types.yml";
my $building_input = "${FindBin::Bin}/building.yml";
my @data_files     = ( qw' data/types.yml data/building.yml ' );
my $output         = "${FindBin::Bin}/../lib/Games/Lacuna/Client/Types.pm";
my $package        = 'Games::Lacuna::Client::Types';
my $template_name  = 'data/Types.tt2';
my $generator      = "data/${FindBin::Script}";

my $template = abs2rel catfile $FindBin::Bin, 'Types.tt2';

my $yaml = LoadFile($input);
unless( $yaml ){
  die "Can't load file '$input'\n";
}

my $tt = Template->new({
});

my $building_data = LoadBuilding->Load($building_input);
my $types = $building_data->types;

my $vars = {
  generator     => $generator,
  package       => $package,
  resource      => $yaml,
  building_meta => $types,
  building_data => $building_data,
  template_name => $template_name,
  data_files    => \@data_files,
};

$tt->process($template, $vars, $output)
  or die;
