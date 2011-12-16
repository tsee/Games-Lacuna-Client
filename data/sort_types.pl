#! /usr/bin/env perl
use strict;
use warnings;
use YAML qw'LoadFile DumpFile';
use List::MoreUtils 'uniq';

use File::Spec::Functions qw'catfile';

use FindBin;

for my $filename ( qw'building.yml' ){
  my $filename = catfile $FindBin::Bin, $filename;
  my $yaml = LoadFile $filename;

  # sort tags
  for my $data ( values %$yaml ){
    my @tags = @{ $data->{tags} };

    # add basic type, if it exists
    if( exists $data->{type} ){
      push @tags, $data->{type};
    }

    @{$data->{tags}} = uniq sort { lc $a cmp lc $b } @tags;
  }

  DumpFile $filename, $yaml;
}
