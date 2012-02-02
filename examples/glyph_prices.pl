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

use Pod::Usage;
if( @ARGV && $ARGV[0] eq '--help' ){
  pod2usage qw'-verbose 2';
}

sub stringify;

print STDERR 'Loading ...';
my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
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
my %glyph_prices_single;
for my $trade ( @trades ){
  my @offers = $trade->offer;
  next unless @offers;

  # skip mixed offers.
  next unless all { $_->type eq 'glyph' } @offers;

  # find the cost per glyph
  my $cost = $trade->cost;
  if( @offers > 1 ){
    $cost = $cost / @offers;
  }else{
    my $glyph = $offers[0]->sub_type;
    unless(
      exists $glyph_prices_single{$glyph}
      &&
      $glyph_prices_single{$glyph} <= $cost
    ){
      $glyph_prices_single{$glyph} = $cost;
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
print "| glyph        |  min  | min_s |  avg  |  max  | count |\n";
print $sep;

my(@glyph,@totals);

# set up for printing
for my $glyph ( keys %glyph_prices ){
  my @prices = @{$glyph_prices{$glyph}};
  my $max   = max @prices;
  my $min   = min @prices;

  # smallest price for single glyph
  my $min_s = $glyph_prices_single{$glyph} || '';

  my $sum   = sum @prices;
  my $mean = $sum / @prices;

  push @glyph, [$glyph,$min,$min_s,$mean,$max,scalar @prices];
  $totals[0] += $min;

  # this isn't quite accurate, but at least it's closer
  if( $min_s ){
    $totals[1] += $min_s;
  }else{
    $totals[1] += $min;
  }

  $totals[2] += $max;
  $totals[3] += $mean;
}

# sort glyphs by their minimum price
@glyph = sort { $a->[1] <=> $b->[1] } @glyph;

# print the body of the table
for my $arr ( @glyph ){
  my($glyph,@n) = @$arr;

  my $pad = ' 'x((12 - length $glyph) / 2);

  printf '| %-12s | ', $glyph;
  my $count = sprintf '%4i ', pop @n;
  @n = map {stringify($_)} @n;
  print join ' | ', @n, $count;
  print " |\n";
}
print $sep;

my $total_glyphs;
$total_glyphs += $_->[5] for @glyph;

# print the averages of each of the columns
print '| averages     | ';
{
  my @prn = map{
    stringify( $_ / @glyph )
  } @totals;
  print join ' | ', @prn, ' --- ';
  print " |\n";
}
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
    my $str = sprintf '%5.2f', $n;
    if( $str =~ /\.00/ ){
      return sprintf '%2i   ', $n;
    }
    $str =~ s/0$/ /;
    return $str;
  }
}
__END__

=head1 NAME

glyph_prices.pl - Reports the prices of glyphs found at the Transporter and Trade Ministry

=head1 SYNOPSIS

glyph_prices.pl [options] [config_file]

[config_file]  is optional and defaults to lacuna.yml

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

This program searches through available trades to find glyphs.

Then it reports several pieces of information that it collected.

=head2 Columns

=over 8

=item B<min>

The minumum amount this glyph costs.

=item B<min_s>

The minimum amount this glyph costs B<by itself>.

=item B<avg>

The average price that this glyph goes for.

=item B<max>

The maximum price that was asked for this glyph.

=item B<count>

How many of this particular glyph is available.

=back

=cut

