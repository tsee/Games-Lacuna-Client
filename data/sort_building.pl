#! /usr/bin/env perl
use strict;
use warnings;
use YAML qw'LoadFile DumpFile';

use FindBin;

my $file = "${FindBin::Bin}/building.yml";
my $yaml = LoadFile $file;

for my $data ( values %$yaml ){
  @{$data->{tags}} = sort @{ $data->{tags} };
}

DumpFile $file, $yaml;
