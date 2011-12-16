#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );

my %opts;
GetOptions(
    \%opts,
    'help',
);

usage() if $opts{help};

my ( $start, $end );

if ( @ARGV == 2 ) {
    $start = $ARGV[0];
    $end   = $ARGV[1];
}
else {
    $start = 6;
    $end   = 30;
}

print "Level | Total\n";
print "------|------\n";

my $total = 0;

for my $i ( $start .. $end ) {

    $total += $i;

    printf "   %2d |   %3d\n",
        $i,
        $total;
}

sub usage {
  die <<"END_USAGE";
Usage:
    $0 X Y
    $0

Prints out the number of Halls of Vrbansk required to upgrade a building
from levels X to Y.

If no arguments are provided, X defaults to 6, Y defaults to 30, which is the
common case of upgrading a building initially made with a 1+5 plan.

END_USAGE

}
