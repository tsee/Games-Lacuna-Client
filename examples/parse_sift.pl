#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long          (qw(GetOptions));
use List::Util            (qw(first max));
use JSON;
use utf8;

  my $log_dir = "log";

  my %opts = (
    h        => 0,
    v        => 0,
    input     => $log_dir . '/sift_shipped.js',
  );

  GetOptions(\%opts,
    'h|help',
    'input=s',
    'v|verbose',
  );
  
  usage() if $opts{h};

  my $json = JSON->new->utf8(1);

  my $idata = get_json($opts{input});
  unless ($idata) {
    die "Could not read $opts{input}\n";
  }
  my $total_g = 0;
  my $total_p = 0;
  for my $ship_id (sort keys %$idata) {
    print "$idata->{$ship_id}->{name} : $ship_id\n";
    my $pmax_length = max map { length $_->{name} } @{$idata->{$ship_id}->{plans}};
    my $gmax_length = max map { length $_->{name} } @{$idata->{$ship_id}->{glyphs}};

    my %plan_out;
    my $ship_p = 0;
    for my $plan (@{$idata->{$ship_id}->{plans}}) {
      my $key = sprintf "%${pmax_length}s, level %2d",
                      $plan->{name},
                      $plan->{level};
        
      if ( $plan->{extra_build_level} ) {
        $key .= sprintf " + %2d", $plan->{extra_build_level};
      }
      else {
        $key .= "     ";
      }
      $plan_out{$key} = $plan->{quantity};
      $ship_p += $plan->{quantity};
    }
    my %glyph_out;
    my $ship_g = 0;
    for my $glyph (@{$idata->{$ship_id}->{glyphs}}) {
      my $key = sprintf "%${gmax_length}s",
                      $glyph->{name};
      $glyph_out{$key} = $glyph->{quantity};
      $ship_g += $glyph->{quantity};
    }
    my $cnt;
    print "Plans:\n";
    for my $key (sort srtname keys %plan_out) {
      print "$key  ($plan_out{$key})\n";
    }
    print "\nGlyphs:\n";
    for my $key (sort srtname keys %glyph_out) {
      print "$key  ($glyph_out{$key})\n";
    }
    printf "\nTotal of %d plans and %d glyphs on %s\n", $ship_p, $ship_g, $idata->{$ship_id}->{name};
    $total_p += $ship_p;
    $total_g += $ship_g;
  }
  printf "\nTotal of %d plans and %d glyphs.\n", $total_p, $total_g;
exit;

sub srtname {
  my $abit = $a;
  my $bbit = $b;
  $abit =~ s/ //g;
  $bbit =~ s/ //g;
  $abit cmp $bbit;
}

sub get_json {
  my ($file) = @_;

  if (-e $file) {
    my $fh; my $lines;
    open($fh, "$file") || die "Could not open $file\n";
    $lines = join("", <$fh>);
    return 0 unless ($lines);
    my $data = $json->decode($lines);
    close($fh);
    return $data;
  }
  else {
    warn "$file not found!\n";
  }
  return 0;
}

sub usage {
    diag(<<END);
Usage: $0 --feedfile file

Options:
  --help            - Prints this out
  --verbose         - Print more details.
  --input  sift  - Where to get data
END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
