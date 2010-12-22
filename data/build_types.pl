#!/usr/bin/perl
use strict;
use warnings;
use YAML::Tiny;
use FindBin;
use File::Spec::Functions qw' abs2rel catfile ';
use Template;

my $input         = "${FindBin::Bin}/types.yml",
my $output        = "${FindBin::Bin}/../lib/Games/Lacuna/Client/Types.pm",
my $package       = 'Games::Lacuna::Client::Types',
my $template_name = 'data/Types.tt2';
my $generator     = "data/${FindBin::Script}";

my $template = abs2rel catfile $FindBin::Bin, 'Types.tt2';

my $yaml = YAML::Tiny->read($input);
unless( $yaml ){
  die "Can't load file '$input'\n";
}

my $tt = Template->new({
});

my $vars = {
  generator     => $generator,
  package       => $package,
  resource      => $yaml->[0]{resource},
  building_meta => $yaml->[0]{building_meta},
  template_name => $template_name,
};

$tt->process($template, $vars, $output)
  or die;
