#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long   qw( GetOptions );
use List::Util     qw( max );
use Number::Format qw( format_number );
use POSIX          qw( floor );

my %opts;
GetOptions(
    \%opts,
    'production',
    'help',
);

usage() if $opts{help};

my $multiplier = $opts{production} ? 1.55
               :                     1.75;

my ( $start, $end );

if ( @ARGV < 2 ) {
    warn "Not Enough Args\n\n";
    usage();
}

my $levels = shift @ARGV;
my @costs  = [ @ARGV ];

# resource costs may be thousand-formatted 1,234,567
# remove any commmas

@costs =
    map {
        s/,//g;
        $_;
    } @costs;

for ( 1 .. $levels ) {
    my $last_level = $costs[$#costs];
    my @this_level;

    for my $i ( @$last_level ) {
        push @this_level, $i*$multiplier;
    }

    push @costs, \@this_level;
}

# format all numbers before counting string lengths
for my $i (@costs) {
    for my $j ( @$i ) {
        $j = format_number( $j, 0 );
    }
}

# count string lengths
my @length = map { 0 } @{ $costs[0] };

for my $i ( 0 .. $#costs ) {
    for my $j ( 0 .. $#{$costs[$i]} ) {
        my $length = length $costs[$i][$j];

        $length[$j] = $length
            if $length > $length[$j];
    }
}

# output

print "Level\n";

for my $i ( 0 .. $#costs ) {
    printf "%5d", $i;

    for my $j ( 0 .. $#{$costs[$i]} ) {
        my $length = $length[$j];

        printf " %${length}s", $costs[$i][$j];
    }

    print "\n";
}


#use Data::Dumper;
#die Dumper(\@costs, \@length);

sub usage {
  die <<"END_USAGE";
Usage:
    $0 LEVELS COST [COST] [COST] [COST]

Prints out the running costs of upgrading a building the specified number of
levels. Each level cost increases by 1.75

    --production
If this option is set, it will treat the arguments as production values instead
of costs, and use a multiplier of 1.55

END_USAGE

}
