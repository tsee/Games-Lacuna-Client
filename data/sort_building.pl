#! /usr/bin/env perl
use strict;
use warnings;
use YAML qw'LoadFile DumpFile';
use List::MoreUtils 'uniq';

use FindBin;

my $file = "${FindBin::Bin}/building.yml";
my $yaml = LoadFile $file;

for my $data ( values %$yaml ){
  my $type = $data->{type};
  @{$data->{tags}} = uniq sort { lc $a cmp lc $b } @{ $data->{tags} }, $type;
}

DumpFile $file, $yaml;
