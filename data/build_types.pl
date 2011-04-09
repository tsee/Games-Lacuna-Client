#!/usr/bin/perl
use strict;
use warnings;
use YAML qw'LoadFile';
use File::Spec::Functions qw' abs2rel catfile ';
use Template;

use FindBin;
use lib "${FindBin::Bin}";
use LoadBuilding;

# TT_var => 'filename',
my %resources = (
  resource => 'resources.yml',
  list => 'lists.yml',
  ship => 'ships.yml',
);

# building_data
my $building_input = "${FindBin::Bin}/building.yml";
my @data_files     = ( qw' data/building.yml ' );

for my $var ( keys %resources ){
  my $filename = $resources{$var};
  my $data = LoadFile( catfile $FindBin::Bin, $filename );

  $filename = 'data/'.$filename;

  unless( $data ){
    die "Can't load file '$filename'\n";
  }

  $resources{$var} = $data;
  push @data_files, $filename;
}
@data_files = sort @data_files;

my $output         = "${FindBin::Bin}/../lib/Games/Lacuna/Client/Types.pm";
my $package        = 'Games::Lacuna::Client::Types';
my $template_name  = 'data/Types.tt2';
my $generator      = "data/${FindBin::Script}";
my $sort_program   = 'data/sort_types.pl';

my $template = abs2rel catfile $FindBin::Bin, 'Types.tt2';


my $tt = Template->new({
});

my $building_data = LoadBuilding->Load($building_input);
my $types = $building_data->types;

my $vars = {
  %resources,
  generator     => $generator,
  sort_program  => $sort_program,
  package       => $package,
  building_meta => $types,
  building_data => $building_data,
  template_name => $template_name,
  data_files    => \@data_files,
};

$tt->process($template, $vars, $output)
  or die;
