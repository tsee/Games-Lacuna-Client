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
use YAML;
use YAML::XS;
use Data::Dumper;
use utf8;

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
my $probe_file = "data/probe_data_cmb.yml";
my $star_file   = "data/stars.csv";
my $statistics  = "data/system_stats.csv";
my $planet_file = "data/planet_score.yml";
my $planet = '';
my $help; my $opt_a = 0; my $opt_g = 0; my $opt_h = 0; my $opt_s; my $nodist = 0;

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
  'systems'      => \$opt_s,
);
  
  usage() if ($help);
  if ($opt_s) {
    $opt_a = $opt_g = $opt_h = 1;
  }

  my $bod;
  my $bodies;
  my $planets;
  if (-e "$probe_file") {
    $bodies  = YAML::XS::LoadFile($probe_file);
  }
  else {
    print STDERR "$probe_file not found!\n";
    die;
  }
  if (-e "$planet_file") {
    $planets = YAML::XS::LoadFile($planet_file);
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
    score_system(\%sys, $bod);
  }
  for my $key (keys %sys) {
    $sys{"$key"}->{sscore} = join(":", $sys{"$key"}->{G}, $sys{"$key"}->{H}, $sys{"$key"}->{A});
  }


  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
         "Name", "Sname", "BS", "SS", "T", "YS", "O", "Dist", "SD", "X", "Y", "Type",
         "Img","Size", "Own", "Zone", "Total", "Mineral", "Amt";
  for $bod (sort byscore @$bodies) {
    next if ($bod->{type} eq "U");
    next if ($bod->{type} eq "A" and $opt_a == 0);
    next if ($bod->{type} eq "G" and $opt_g == 0);
    next if ($bod->{type} eq "H" and $opt_h == 0);
    next if ($bod->{dist} > $max_dist);
  
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
           $bod->{name}, $bod->{star_name}, $bod->{bscore},
           $sys{"$bod->{star_id}"}->{sscore}, $sys{"$bod->{star_id}"}->{T},
           $sys{"$bod->{star_id}"}->{YS},
           $bod->{orbit}, $bod->{dist}, $bod->{sdist}, $bod->{x}, $bod->{y},
           $bod->{type}, $bod->{image}, $bod->{size}, $bod->{empire}->{name},
           $bod->{zone}, $bod->{ore_total};
    for my $ore (sort keys %{$bod->{ore}}) {
      if ($bod->{ore}->{$ore} > 1) {
        print "\t$ore\t", $bod->{ore}->{$ore};
      }
    }
    print "\n";
  }
exit;

# Highly Arbritrary system for scoring a star system based on what is in it.
sub score_system {
  my ($sys, $bod) = @_;


  unless (defined($sys->{"$bod->{star_id}"}) ) {
    $sys->{"$bod->{star_id}"}->{sscore} = "";
    $sys->{"$bod->{star_id}"}->{A} = 0;
    $sys->{"$bod->{star_id}"}->{G} = 0;
    $sys->{"$bod->{star_id}"}->{H} = 0;
    $sys->{"$bod->{star_id}"}->{T} = 0;
    $sys->{"$bod->{star_id}"}->{YS} = 0;
  }
  $sys{"$bod->{star_id}"}->{YS} += $bod->{bscore};

  if ($bod->{type} eq "H") {
    if ( ($bod->{orbit} == 1 or $bod->{orbit} == 7) &&
         ($bod->{size} >= MIN_H1)) {
      $sys->{"$bod->{star_id}"}->{H} += 1;
      
    }
    elsif ( ($bod->{orbit} == 3) and
         ($bod->{size} >= MIN_H3)) {
      $sys->{"$bod->{star_id}"}->{H} += 1;
    }
    elsif ( ($bod->{orbit} >= 2 and $bod->{orbit} <= 6) &&
         ($bod->{size} >= MIN_H5)) {
      $sys->{"$bod->{star_id}"}->{H} += 1;
    }
  }
  elsif ($bod->{type} eq "G") {
    if ( ($bod->{orbit} == 1 or $bod->{orbit} == 7) &&
         ($bod->{size} >= MIN_G1)) {
      $sys->{"$bod->{star_id}"}->{G} += 1;
    }
    elsif ( ($bod->{orbit} >= 2 and $bod->{orbit} <= 6) &&
         ($bod->{size} >=  MIN_G5)) {
      $sys->{"$bod->{star_id}"}->{G} += 1;
    }
  }
  elsif ($bod->{type} eq "A") {
    my $ascore = score_atype($bod->{image});
    if ( $ascore > MIN_A) {
      $sys->{"$bod->{star_id}"}->{A} += 1;
    }
  }
  else {
    $sys->{"$bod->{star_id}"}->{A} += 0;
  }
  if ($bod->{type} eq "U") {
    $sys->{"$bod->{star_id}"}->{T} += 0
  }
  elsif ($bod->{type} eq "A" or ($bod->{orbit} == 1 or $bod->{orbit} >= 7)) {
    if ($bod->{orbit} == 8) {
      $sys->{"$bod->{star_id}"}->{T} += int($bod->{size}/3+0.5);
    }
    else {
      $sys->{"$bod->{star_id}"}->{T} += int($bod->{size}/2+0.5);
    }
  }
  else {
    $sys->{"$bod->{star_id}"}->{T} += $bod->{size};
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

sub get_stars {
  my ($sfile) = @_;

  my $fh;
  open ($fh, "<", "$sfile") or die;

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
