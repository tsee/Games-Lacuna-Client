#!/usr/bin/perl 
use strict;
use warnings;

use List::Util qw'max min sum';
use List::MoreUtils qw'all none part';
use Scalar::Util qw'dualvar';

use FindBin;
use lib "${FindBin::Bin}/../lib";
use Games::Lacuna::Client::Market;
use Games::Lacuna::Client::Types qw'ore_types';

if( @ARGV && $ARGV[0] eq '--help' ){
  print <<HELP;
usage: ${FindBin::Script} [config_file]
  prints out a table of currently available glyphs.

( config_file defaults to lacuna.yml )
HELP
exit(0);
}

sub stringify;

print STDERR 'Loading ...';
my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  die "Did not provide a config file";
}

my $market = Games::Lacuna::Client::Market->new(
  cfg_file => $cfg_file,
  filter   => 'glyph',
);

# load trades
my @trades = (
  $market->available_trades( building => 'Trade' ),
  $market->available_trades( building => 'Transporter' ),
);
undef $market;

# convert the trade information to a more useful form
my %glyph_prices;
for my $trade ( @trades ){
  my @offers = $trade->offer;
  next unless @offers;
  
  # skip mixed offers.
  next unless all { $_->type eq 'glyph' } @offers;
  
  # find the cost per glyph
  my $cost = $trade->cost;
  if( @offers > 1 ){
    $cost = $cost / @offers;
    
    # force it to be fractional
    if( $cost != int $cost ){
      $cost += 0.0000001;
    }
  }
  
  for my $offer ( @offers ){
    push @{ $glyph_prices{$offer->sub_type} }, $cost;
  }
}

print STDERR "\r".(' 'x20)."\r";

# separator for our table
my $sep = '+'.('-'x14).( ('+'.('-'x7))x5 )."+\n";

print $sep;
print "| glyph        |  #    |  min  | min_s |  avg  |  max  |\n";
print $sep;

my(@glyph,@totals);

# set up for printing
for my $glyph ( keys %glyph_prices ){
  my @prices = @{$glyph_prices{$glyph}};
  my $max   = max @prices;
  my $min   = min @prices;
  
  # smallest price for single glyph
  my $min_s = min grep { $_ == int $_ } @prices;
  
  my $sum   = sum @prices;
  my $mean = $sum / @prices;
  my $count = @prices;
  
  push @glyph, [$glyph, $count, $min,$min_s,$mean,$max];
  $totals[0] += $count;
  $totals[1] += $min;
  $totals[2] += $min_s;
  $totals[3] += $max;
  $totals[4] += $mean;
}

# sort glyphs by their minimum price
@glyph = sort { $a->[2] <=> $b->[2] } @glyph;

# print the body of the table
for my $arr ( @glyph ){
  my($glyph,@n) = @$arr;
  
  my $pad = ' 'x((12 - length $glyph) / 2);
  
  printf '| %-12s | ', $glyph;
  print join ' | ', map {stringify($_)} @n;
  print " |\n";
}
print $sep;

# print the averages of each of the columns
print '| averages     | ';
print join ' | ', map {
  stringify( $_ / @glyph )
} @totals;
print " |\n";
print $sep;

# done printing table

# find unavailable glyphs
my @list = keys %glyph_prices;
my @missing = grep {
  my $a = $_;
  none { $_ eq $a } @list
} ore_types;

# if there are any missing glyphs, print them out
if( @missing ){
  my $i = 0;
  my @part = part { $i++ / 3 } @missing; #/
  print "  Unavailable:\n";
  for( @part ){
    printf "    %-14s %-14s %-14s\n", @$_, ('')x2;
  }
}


# function that simplifies printing of the table
sub stringify{
  my($n) = (@_,$_);
  
  return ' 'x5 unless length $n;
  
  if( $n == int $n ){
    return sprintf '%2i   ', $n;
  }else{
    my $str = sprintf '%05.2f', $n;
    if( $str =~ /\.00/ ){
      return sprintf '%2i   ', $n;
    }
    $str =~ s/0$/ /;
    $str =~ s/^0/ /;
    return $str;
  }
}

