#!/usr/bin/perl
#
# Script to parse thru the probe data and try to
# score each body and systems by arbritray standards
#
# Usage: perl score_bodies.pl
#
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON;
use utf8;
binmode STDOUT, ":utf8";

# Constants used for what is a decent sized planet
use constant {
  MIN_H1 =>  55,  # Orbits 1 and 7
  MIN_H3 =>  50,  # Orbit  3
  MIN_H5 =>  55,  # Orbit  other
  MIN_G1 =>  95,  # Orbits 1 and 7
  MIN_G5 =>  95,  # Orbit other
  MIN_A  =>   1,  # Asteroid score
};

my $home_x;
my $home_y;
my $max_dist = 5000;
my $probe_file = "data/probe_data_cmb.js";
my $star_file   = "data/stars.csv";
my $statistics  = "data/system_stats.csv";
my $planet_file = "data/planet_score.js";
my $planet = '';
my $help; my $opt_a = 0; my $opt_g = 0; my $opt_h = 0; my $opt_o = 0; my $opt_s = 0; my $nodist = 0;

GetOptions(
  'x=i'          => \$home_x,
  'y=i'          => \$home_y,
  'planet=s'     => \$planet,
  'max_dist=i'   => \$max_dist,
  'nodist'       => \$nodist,
  'probe=s'      => \$probe_file,
  'stars=s'      => \$star_file,
  'statistics=s' => \$statistics,
  'help'         => \$help,
  'asteroid'     => \$opt_a,
  'gas'          => \$opt_g,
  'habitable'    => \$opt_h,
  'stations'     => \$opt_s,
  'systems'      => \$opt_o,
);

  usage() if ($help);
  if ($opt_o) {
    $opt_a = $opt_g = $opt_h = $opt_s = 1;
  }

  my $json = JSON->new->utf8(1);

  my $bod;
  my $bodies;
  my $planets;
  if (-e "$probe_file") {
    my $pf;
    open($pf, "$probe_file") || die "Could not open $probe_file\n";
    my $lines = join("", <$pf>);
    $bodies = $json->decode($lines);
    close($pf);
  }
  else {
    print STDERR "$probe_file not found!\n";
    die;
  }
  if (-e "$planet_file") {
    my $pf;
    open($pf, "$planet_file") || die "Could not open $planet_file\n";
    my $lines = join("", <$pf>);
    $planets = $json->decode($lines);
    close($pf);
  }
  else {
    unless (defined($home_x) and defined($home_y)) {
      print STDERR "$planet_file not found!\n";
      die;
    }
  }
  unless (defined($home_x) and defined($home_y)) {
    ($home_x, $home_y) = get_coord($planets, $planet);
  }

  my $stars;
  if (-e "$star_file") {
    $stars  = get_stars("$star_file");
  }
  else {
    print STDERR "$star_file not found!\n";
    die;
  }

  my %sys;

# Calculate some metadata
  for $bod (@$bodies) {
    if (not defined($bod->{water}) or $bod->{water} eq '') { $bod->{water} = 0; }
    if (not defined($bod->{zone})) { $bod->{zone} = 0; }
    $bod->{size} = 0 if ($bod->{size} eq '');
    unless (defined($bod->{empire})) { $bod->{empire}->{name} = "unclaimed"; }
    unless (defined($bod->{star_name})) { $bod->{star_name} = ""; }
    $bod->{image} =~ s/-.//;
    $bod->{dist}  = sprintf("%.2f", sqrt(($home_x - $bod->{x})**2 + ($home_y - $bod->{y})**2));
    $bod->{sdist} = sprintf("%.2f", sqrt(($home_x - $stars->{$bod->{star_id}}->{x})**2 +
                                         ($home_y - $stars->{$bod->{star_id}}->{y})**2));
    $bod->{ore_total} = 0;
    for my $ore_s (keys %{$bod->{ore}}) {
      if ($bod->{ore}->{$ore_s} eq '') { $bod->{ore}->{$ore_s} = 0; }
      if ($bod->{ore}->{$ore_s} > 1) { $bod->{ore_total} += $bod->{ore}->{$ore_s}; }
    }
    if ($bod->{type} eq "asteroid") {
      $bod->{type} = "A";
      $bod->{bscore} = score_rock($bod, $nodist);
    }
    elsif ($bod->{type} eq "gas giant") {
      $bod->{type} = "G";
      $bod->{bscore} = score_gas($bod, $nodist);
    }
    elsif ($bod->{type} eq "habitable planet") {
      $bod->{type} = "H";
      $bod->{bscore} = score_planet($bod, $nodist);
    }
    elsif ($bod->{type} eq "space station") {
      $bod->{type} = "S";
      $bod->{bscore} = 0;
    }
    else {
      $bod->{type} = "U";
      $bod->{bscore} = 0;  #erk
    }
    score_system_fp(\%sys, $bod);
  }
  for my $key (keys %sys) {
    $sys{"$key"}->{sscore} = join(":", $sys{"$key"}->{G}, $sys{"$key"}->{H}, $sys{"$key"}->{A});
    $sys{"$key"}->{gscore} = join(":", $sys{"$key"}->{G}, $sys{"$key"}->{HA});
    $sys{"$key"}->{FW} = score_foodw($sys{$key}->{FRNG});
  }
  print STDERR scalar keys %sys, " systems and ", scalar @$bodies, " bodies checked.\n";


  my @fields = ( "Name", "Sname", "BS", "SS", "GG", "TS", "TBS", "TCS", "TYS", "TCYS", "FW", "O", "Dist",
                 "SD", "X", "Y", "Type", "Img","Size", "Own", "Zone", "Water", "Total", "Mineral", "Amt");
  printf "%s\t" x scalar @fields, @fields;
  print "\n";
  for $bod (sort byfw @$bodies) {
    next if ($bod->{type} eq "U");
    next if ($bod->{type} eq "A" and $opt_a == 0);
    next if ($bod->{type} eq "G" and $opt_g == 0);
    next if ($bod->{type} eq "H" and $opt_h == 0);
    next if ($bod->{type} eq "S" and $opt_s == 0);
    next if ($bod->{dist} > $max_dist);

    printf "%s\t" x ( scalar @fields - 2),
           $bod->{name}, $bod->{star_name}, $bod->{bscore},
           $sys{"$bod->{star_id}"}->{sscore}, $sys{"$bod->{star_id}"}->{gscore},
           $sys{"$bod->{star_id}"}->{TS}, $sys{"$bod->{star_id}"}->{TBS},
           $sys{"$bod->{star_id}"}->{TCS}, $sys{"$bod->{star_id}"}->{TYS},
           $sys{"$bod->{star_id}"}->{TCYS}, $sys{"$bod->{star_id}"}->{FW},
           $bod->{orbit}, $bod->{dist}, $bod->{sdist}, $bod->{x}, $bod->{y},
           $bod->{type}, $bod->{image}, $bod->{size}, $bod->{empire}->{name},
           $bod->{zone}, $bod->{water}, $bod->{ore_total};
    for my $ore (sort keys %{$bod->{ore}}) {
      if ($bod->{ore}->{$ore} > 1) {
        print $ore,"\t", $bod->{ore}->{$ore},"\t";
      }
    }
    print "\n";
  }
exit;

sub score_foodw {
  my ($size_a) = @_;

  my $score = 0;
  my $skip = 0;
  my $num;
  for $num (2..4) {
    if ($size_a->[$num] >= 50 and $size_a->[$num] < 70) {
      $score += 1;
    }
    elsif ($size_a->[$num] > 95) {
      $score += 1;
    }
    else {
      $skip = 1;
    }
  }

  my $pass_5 = 0;
  my $pass_6 = 0;
  if ($size_a->[5] >= 50 and $size_a->[5] < 70) {
    $score += 1;
    $pass_5 = 1;
  }
  elsif ($size_a->[5] >= 95) {
    $score += 1;
    $pass_5 = 1;
  }
  if ($size_a->[6] >= 50 and $size_a->[6] < 70) {
    $score += 1;
    $pass_6 = 1;
  }
  elsif ($size_a->[6] >= 95) {
    $score += 1;
    $pass_6 = 1;
  }
  $skip = 1 unless ($pass_5 + $pass_6);

  return $score if $skip;
  for $num (1..7) {
    if ($size_a->[$num] >= 95) {
      $score += 1;
    }
  }
  for $num (1,7) {
    if ($size_a->[$num] >= 55 and $size_a->[$num] < 70) {
      $score += 1;
    }
    elsif ($size_a->[$num] >= 95) {
      $score += 1;
    }
    else {
      $skip = 1;
    }
  }
  return $score if $skip;
  if ($size_a->[8] >= 55 and $size_a->[8] < 70) {
    $score += 1;
  }
  elsif ($size_a->[8] >= 95) {
    $score += 1;
  }
  return $score;
}

# Highly Arbritrary system for scoring a star system based on what is in it.
sub score_system_fp {
  my ($sys, $bod) = @_;

  my $star_id = $bod->{star_id};

  unless (defined($sys->{"$star_id"}) ) {
    $sys->{"$star_id"}->{sscore} = "";
    $sys->{"$star_id"}->{A} = 0; # Decent Asteroids
    $sys->{"$star_id"}->{G} = 0; # Decent Gas Giants
    $sys->{"$star_id"}->{H} = 0; # Decent Habitable
    $sys->{"$star_id"}->{HA} = 0; # Looking for right size Gas Giants, plan to Blackhole the rest
    $sys->{"$star_id"}->{TS} = 0; # Total size
    $sys->{"$star_id"}->{TBS} = 0; # Total Base score
    $sys->{"$star_id"}->{TCS} = 0; # Total Size of H & G
    $sys->{"$star_id"}->{TYS} = 0; # Total H & G Orbits 2-6
    $sys->{"$star_id"}->{TCYS} = 0; # Total H & G, if > min
    $sys->{"$star_id"}->{FW} = 0; # Threshold scoring
    $sys->{"$star_id"}->{FRNG} = [ (0) x 9 ];
  }

  $sys->{"$star_id"}->{FRNG}->[$bod->{orbit}] = $bod->{size};

  $sys->{"$star_id"}->{TS} += $bod->{size};
  $sys->{"$star_id"}->{TBS} += $bod->{bscore};

  if ($bod->{type} eq "H" or $bod->{type} eq "G") {
    $sys->{"$star_id"}->{TCS} += $bod->{size};
    if ($bod->{orbit} >= 2 and $bod->{orbit} <= 6) {
      $sys->{"$star_id"}->{TYS} += $bod->{size};
    }
  }

  if ($bod->{type} eq "H") {
    if ( ($bod->{orbit} == 1 or $bod->{orbit} == 7) &&
         ($bod->{size} >= MIN_H1)) {
      $sys->{"$star_id"}->{H} += 1;
      $sys->{"$star_id"}->{TCYS} += $bod->{size};
    }
    elsif ( ($bod->{orbit} == 3) and
         ($bod->{size} >= MIN_H3)) {
      $sys->{"$star_id"}->{H} += 1;
      $sys->{"$star_id"}->{TCYS} += $bod->{size};
    }
    elsif ( ($bod->{orbit} >= 2 and $bod->{orbit} <= 6) &&
         ($bod->{size} >= MIN_H5)) {
      $sys->{"$star_id"}->{H} += 1;
      $sys->{"$star_id"}->{TCYS} += $bod->{size};
    }
    $sys->{"$star_id"}->{HA} += 1;
  }
  elsif ($bod->{type} eq "G") {
    if ( ($bod->{orbit} == 1 or $bod->{orbit} == 7) &&
         ($bod->{size} >= MIN_G1)) {
      $sys->{"$star_id"}->{G} += 1;
      $sys->{"$star_id"}->{TCYS} += $bod->{size};
    }
    elsif ( ($bod->{orbit} >= 2 and $bod->{orbit} <= 6) &&
         ($bod->{size} >=  MIN_G5)) {
      $sys->{"$star_id"}->{G} += 1;
      $sys->{"$star_id"}->{TCYS} += $bod->{size};
    }
  }
  elsif ($bod->{type} eq "A") {
    my $ascore = score_atype($bod->{image});
    if ( $ascore > MIN_A) {
      $sys->{"$star_id"}->{A} += 1;
    }
    $sys->{"$star_id"}->{HA} += 1;
  }
  else {
    $sys->{"$star_id"}->{A} += 0;
  }
}

sub score_rock {
  my ($bod, $nodist) = @_;

  my $score = 0;

  unless ($nodist) {
    if ($bod->{dist} < 11) { $score += 20; }
    elsif ($bod->{dist} < 21) { $score += 15; }
    elsif ($bod->{dist} < 31) { $score += 10; }
    elsif ($bod->{dist} < 51) { $score += 5; }
  }

  $score += score_atype($bod->{image}) * 5;

  return $score;
}

sub score_atype {
  my ($atype) = @_;

  if    ($atype eq "a1" )  { return  4; }
  elsif ($atype eq "a2" )  { return  4; }
  elsif ($atype eq "a3" )  { return  4; }
  elsif ($atype eq "a4" )  { return  4; }
  elsif ($atype eq "a5" )  { return  3; }
  elsif ($atype eq "a6" )  { return -2; }
  elsif ($atype eq "a7" )  { return  0; }
  elsif ($atype eq "a8" )  { return  0; }
  elsif ($atype eq "a9" )  { return -1; }
  elsif ($atype eq "a10" ) { return  1; }
  elsif ($atype eq "a11" ) { return  3; }
  elsif ($atype eq "a12" ) { return  6; }
  elsif ($atype eq "a13" ) { return  3; }
  elsif ($atype eq "a14" ) { return  2; }
  elsif ($atype eq "a15" ) { return  1; }
  elsif ($atype eq "a16" ) { return  1; }
  elsif ($atype eq "a17" ) { return -3; }
  elsif ($atype eq "a18" ) { return  2; }
  elsif ($atype eq "a19" ) { return  2; }
  elsif ($atype eq "a20" ) { return  0; }
  elsif ($atype eq "a21" ) { return 99; }

  return 0;
}

sub score_planet {
  my ($bod, $nodist) = @_;

  my $score = 0;
  if ($bod->{size} >= 60 or ($bod->{size} >= 55 && $bod->{orbit} == 3)) {
    $score += 50;
  }
  else { $score += ($bod->{size} - 50 ) * 2; }

  unless ($nodist) {
    if ($bod->{dist} < 11) { $score += 20; }
    elsif ($bod->{dist} < 21) { $score += 15; }
    elsif ($bod->{dist} < 31) { $score += 10; }
    elsif ($bod->{dist} < 51) { $score += 5; }
  }

  if ($bod->{water} > 9000) { $score += 15; }
  elsif ($bod->{water} > 7000) { $score += 10; }
  elsif ($bod->{water} > 6000) { $score += 5; }

  return $score;
}

sub score_gas {
  my ($bod, $nodist) = @_;

  my $score = 0;
  if ($bod->{size} >= 121) {
    $score += 60;
  }
  elsif ($bod->{size} > 116) {
    $score += 50;
  }
  elsif ($bod->{size} > 100) {
    $score += 25;
  }
  elsif ($bod->{size} > 90) {
    $score += 5;
  }

  unless ($nodist) {
    if ($bod->{dist} < 11) {
      $score += 20;
    }
    elsif ($bod->{dist} < 21) {
      $score += 15;
    }
    elsif ($bod->{dist} < 31) {
      $score += 10;
    }
    elsif ($bod->{dist} < 51) {
      $score += 5;
    }
  }
  return $score;
}

sub byscore {
   $b->{bscore} <=> $a->{bscore} ||
   $a->{dist} <=> $b->{dist} ||
   $a->{name} cmp $b->{name};
}

sub byfw {
  $sys{"$b->{star_id}"}->{FW}   <=> $sys{"$a->{star_id}"}{FW} ||
  $sys{"$b->{star_id}"}->{TCYS} <=> $sys{"$a->{star_id}"}{TCYS} ||
  $sys{"$b->{star_id}"}->{TYS}  <=> $sys{"$a->{star_id}"}{TYS} ||
  $a->{orbit} <=> $b->{orbit};
}

sub get_stars {
  my ($sfile) = @_;

  my $fh;
  open ($fh, "<:utf8", "$sfile") or die;

  my $fline = <$fh>;
  my %star_hash;
  while(<$fh>) {
    chomp;
    my ($id, $name, $x, $y, $color, $zone) = split(/,/, $_, 6);
    $star_hash{$id} = {
      id    => $id,
      name  => $name,
      x     => $x,
      y     => $y,
      color => $color,
      zone  => $zone,
    }
  }
  return \%star_hash;
}

sub get_coord {
  my ($planets, $pname) = @_;

#  print "$pname : ", join(":", keys %{$planets}), "\n";
  my ($prime) = grep { $planets->{$_}->{prime} } keys %{$planets};
#  print "Planet: $prime\n";
  my $px = $planets->{"$prime"}->{x};
  my $py = $planets->{"$prime"}->{y};

#  print $px, $py, "\n";
  if (defined($planets->{"$pname"})) {
    return $planets->{"$pname"}->{x}, $planets->{"$pname"}->{y};
  }
  return $px, $py

}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program takes your supplied probe file and spits out information on the bodies in question.
Score is based totally on subjective opinion and what the author was looking for at the time.
Probe file generation by probe_yaml.pl and merge_probe.pl

Options:
  --help      - Prints this out
  --x Num     - X coord for distance calculation
  --y Num     - X coord for distance calculation
  --p probe   - probe_file,
  --asteroid  - If looking at asteroid stats
  --gas       - If looking at gas giant stats
  --habitable - If looking at habitable stats
  --systems   - If looking at a whole system.
END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
