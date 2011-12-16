#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use POSIX        qw( floor );

my %opts;
GetOptions(
    \%opts,
    'help',
);

usage() if $opts{help};

my ( $start, $end );

if ( @ARGV == 1 ) {
    $start = $end = $ARGV[0];
}
elsif ( @ARGV == 2 ) {
    $start = $ARGV[0];
    $end   = $ARGV[1];
}
else {
    $start = 1;
    $end   = 30;
}

print "Level | Cost | Total\n";
print "------|------|------\n";

my $total = 0;

for my $i ( $start .. $end ) {

    my $cost = floor( $i / 3 )
            || 1;

    $total += $cost;

    printf "   %2d |   %2d |   %3d\n",
        $i,
        $cost,
        $total;
}

sub usage {
  die <<"END_USAGE";
Usage:
    $0 X Y
    $0 X
    $0

Prints out the Essentia costs of subsidizing building upgrade times from
levels X to Y.

If no arguments are provided, X defaults to 1, Y defaults to 30.

END_USAGE

}
