#!/usr/bin/perl
use strict;
use warnings;
use LWP::Simple;

use FindBin;

my $url = 'https://github.com/plainblack/Lacuna-Web-Client/raw/master/smd.js';

my $js = get($url);

# skip if it is actually json
unless( $js =~ /^\s*{/s ){
  $js =~ s/^.*?var smd = {/{/s;
  $js =~ s/};.*/}/s;
  $js =~ s(^\s*/\*.*?\*/){}smg;
  $js =~ s(\s*//.*){}mg;
  $js =~ s/^\t//mg;
  $js =~ s/^(\s*)(\w+)(\s*:\s*{)/$1"$2"$3/mg;
  $js =~ s/\s+$//mg;
}

open  my $json_fh, '>', "${FindBin::Bin}/smd.json";
print {$json_fh} $js;
close $json_fh;
