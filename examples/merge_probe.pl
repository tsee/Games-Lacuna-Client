#!/usr/bin/perl
#
# Script to parse thru the probe data
#
# Usage: perl parse_probe.pl probe_file
#
# Write this to put out system stats
#
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON;
use utf8;

my $import_file = "data/probe_data_raw.js";
my $merge_file  = "data/probe_data_cmb.js";
my $star_file   = "data/stars.csv";
my $help = 0;

GetOptions(
  'help'     => \$help,
  'import=s' => \$import_file,
  'merge=s'  => \$merge_file,
  'stars=s'  => \$star_file,
);

  usage() if $help;

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);

  my $imp_f; my $mrg_f; my $new_f; my $lines;
  open($imp_f, "$import_file") || die "Could not open $import_file\n";
  $lines = join("", <$imp_f>);
  my $import = $json->decode($lines);
  close($imp_f);

  open($mrg_f, "$merge_file") || die "Could not open $merge_file\n";
  $lines = join("", <$mrg_f>);
  my $merged = $json->decode($lines);
  close($mrg_f);

  my $stars;
  if (-e "$star_file") {
    $stars  = get_stars("$star_file");
  }
  else {
    print STDERR "$star_file not found!\n";
    die;
  }

  my %mhash;
  my %checked;
  for my $elem (@$merged) {
    my $mkey = join("","x:",$elem->{x},"y:",$elem->{y});
    unless (defined($elem->{observatory})) {
      $elem->{observatory}->{empire} = "none",
      $elem->{observatory}->{oid} = 0,
      $elem->{observatory}->{pid} = 0,
      $elem->{observatory}->{pname} = "none",
      $elem->{observatory}->{stime} = 0,
      $elem->{observatory}->{ststr} = "",
    }
    if (defined($mhash{$mkey})) {
      if ($elem->{observatory}->{stime} > $mhash{$mkey}->{observatory}->{stime}) {
        $mhash{$mkey} = $elem;
      }
      print STDERR "$mkey dupe!\n"; # This shouldn't actually happen
    }
    else {
      $mhash{$mkey} = $elem;
    }
  }
  for my $elem ( @$import ) {
    my $mkey = join("","x:",$elem->{x},"y:",$elem->{y});
    unless (defined($elem->{observatory})) {
      $elem->{observatory}->{empire} = "none",
      $elem->{observatory}->{oid} = 0,
      $elem->{observatory}->{pid} = 0,
      $elem->{observatory}->{pname} = "none",
      $elem->{observatory}->{stime} = 0,
      $elem->{observatory}->{ststr} = "",
    }
    if (defined($mhash{$mkey})) {
#      print "Updating $mhash{$mkey}->{name}\n";
      check_sname($elem, $stars);
      $mhash{$mkey} = merge_probe($mhash{$mkey}, $elem);
    }
    else {
      unless (defined($checked{"$elem->{star_id}"})) {
        print "Adding $elem->{name}\n";
        $checked{"$elem->{star_id}"} = 1;
      }
      check_sname($elem, $stars);
      $mhash{$mkey} = $elem;
    }
  }
  my @merged = map { $mhash{$_} } sort keys %mhash;

  open($new_f, ">", "$merge_file") || die "Could not open $merge_file\n";
  print $new_f $json->pretty->canonical->encode(\@merged);
  close($new_f);
exit;

sub merge_probe {
  my ($orig, $data) = @_;

  my $orig_m = [ "nobody", ];
  $orig_m = $orig->{observatory}->{moved} if (defined($orig->{observatory}->{moved}));
  my $data_m = [ "nobody", ];
  $data_m = $data->{observatory}->{moved} if (defined($data->{observatory}->{moved}));

  my $orig_e = '';
  $orig_e = $orig->{empire}->{name} if (defined($orig->{empire}));
  my $data_e = '';
  $data_e = $data->{empire}->{name} if (defined($data->{empire}));

  if (defined($data->{last_excavated})) {
    $orig->{last_excavated} = $data->{last_excavated};
  }
  if ($orig->{observatory}->{stime} > $data->{observatory}->{stime}) {
    printf "Adding old move data to $orig->{name}\n";
    $orig->{observatory}->{moved} = update_vacate($orig_m, $data_m, $orig_e, $data_e);
  }
  else {
    my $old_own = ownership_test($orig, $orig_e);
    $orig->{observatory}->{moved} = update_vacate($data_m, $orig_m, $data_e, $orig_e);
    $orig->{name} = $data->{name};
    $orig->{observatory}->{empire} = $data->{observatory}->{empire};
    $orig->{observatory}->{oid} = $data->{observatory}->{oid};
    $orig->{observatory}->{pid} = $data->{observatory}->{pid};
    $orig->{observatory}->{pname} = $data->{observatory}->{pname};
    $orig->{observatory}->{stime} = $data->{observatory}->{stime};
    $orig->{observatory}->{ststr} = $data->{observatory}->{ststr};
    if ($data_e ne '') {
      print "Empire Info update for $orig->{name}\n" unless ($orig_e eq '' or cmp_emp($orig, $data));
      $orig->{empire}->{alignment}       = $data->{empire}->{alignment};
      $orig->{empire}->{id}              = $data->{empire}->{id};
      $orig->{empire}->{is_isolationist} = $data->{empire}->{is_isolationist};
      $orig->{empire}->{name}            = $data->{empire}->{name};
    }
    my $new_own = ownership_test($orig, $orig_e);
    unless (defined($checked{"$orig->{star_id}"})) {
      printf "Importing $orig->{name}\n" if ($old_own ne $new_own);
      $checked{"$orig->{star_id}"} = 1;
    }
    if ($orig_e ne "" and $data_e eq "") {
      delete $orig->{empire};
      delete $orig->{building_count};
      delete $orig->{energy_capacity};
      delete $orig->{energy_hour};
      delete $orig->{energy_stored};
      delete $orig->{food_capacity};
      delete $orig->{food_hour};
      delete $orig->{food_stored};
      delete $orig->{happiness};
      delete $orig->{happiness_hour};
      delete $orig->{needs_surface_refresh};
      delete $orig->{ore_capacity};
      delete $orig->{ore_hour};
      delete $orig->{ore_stored};
      delete $orig->{plots_available};

      delete $orig->{population};
      delete $orig->{waste_capacity};
      delete $orig->{waste_hour};
      delete $orig->{waste_stored};
      delete $orig->{water_capacity};
      delete $orig->{water_hour};
      delete $orig->{water_stored};
    }
  }
  if ($orig->{star_name} ne $data->{star_name}) {
    printf "Starname changed from %s to %s.\n",
             $orig->{star_name}, $data->{star_name};
    $orig->{star_name} = $data->{star_name};
  }
  if (defined($data->{station})) {
    if (!defined($orig->{station})) {
      printf "Star %s has been claimed by Station: %s!\n",
              $data->{star_name}, $data->{station}->{name};
      %{$orig->{station}} = %{$data->{station}};
    }
    elsif ($data->{station}->{name} ne $orig->{station}->{name}) {
      printf "Star %s has been claimed by Station: %s from Station: %s!\n",
              $data->{star_name}, $data->{station}->{name},
              $orig->{station}->{name};
      %{$orig->{station}} = %{$data->{station}};
    }
  }
  if ($orig->{type} ne $data->{type} or  # We probably have a new space station or asteroid to account for
      $orig->{size} ne $data->{size} or  # Some size changes to account for
      $orig->{star_id} ne $data->{star_id} # A planet got moved.
     ) {
    printf "Changing type:size:star_id of %s from %s:%s:%d:%s to %s:%s:%d:%s\n",
             $data->{name}, $orig->{image}, $orig->{type}, $orig->{size}, $orig->{star_id},
             $data->{image}, $data->{type}, $data->{size}, $data->{star_id};
    $orig = copy_body($orig, $data);
  }
  return $orig;
}

sub cmp_emp {
  my ($orig, $data) = @_;

  my $str1 = join(":", $orig->{empire}->{alignment}, $orig->{empire}->{id},
                       $orig->{empire}->{is_isolationist}, $orig->{empire}->{name});
  my $str2 = join(":", $data->{empire}->{alignment}, $data->{empire}->{id},
                       $data->{empire}->{is_isolationist}, $data->{empire}->{name});

  if ($str1 eq $str2) {
    return 1;
  }
  return 0;
}

sub copy_body {
  my($orig, $data) = @_;
#Easier to swap info into new and return it.
  if (defined($orig->{empire})) {
    %{$data->{empire}} = %{$orig->{empire}};
  }
  if (defined($orig->{observatory})) {
    %{$data->{observatory}} = %{$orig->{observatory}};
  }
  return $data;
}

sub ownership_test {
  my ($elem, $ename) = @_;
  return join(":",$elem->{name}, $elem->{observatory}->{empire},
              $elem->{observatory}->{oid}, $elem->{observatory}->{pid}, $ename);
}

sub update_vacate {
  my ($curr_m, $updt_m, $curr_e, $updt_e) = @_;

  if ($updt_e ne '' and $curr_e ne $updt_e) {
      push @{$curr_m}, $updt_e;
  }
  push @{$curr_m}, @{$updt_m};
  my %thash;
  for (@{$curr_m}) {
    $thash{$_} = 1 if ($_ ne '' and $_ ne "nobody");
  }
  my @new_t = sort keys %thash;
  if (scalar @new_t == 0) {
    $new_t[0] = "nobody";
  }
#  print STDERR $curr_e, " - ", join(",", @new_t),"\n";
  return \@new_t;
}

sub check_sname {
  my ($elem, $stars) = @_;
  unless (defined($elem->{star_name})) {
    $elem->{star_name} = $stars->{$elem->{star_id}}->{name};
  }
  $elem->{star_name} =~ y/"'//d;
#  if ($elem->{star_name} ne $stars->{$elem->{star_id}}->{name}) {
#    $elem->{star_name} = $stars->{$elem->{star_id}}->{name};
#  }
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

sub usage {
    diag(<<END);
Usage: $0 [options]

This program takes all data from two probe files and merges them.

Options:

  --help                 - Prints this out
  --import <file>        - File to import, default: data/probe_data_raw.js
  --merge  <file>        - Main file to merge into, default: data/probe_data_cmb.js

END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
