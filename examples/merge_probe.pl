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
use YAML::XS;
use utf8;

my $import_file = "data/probe_data_raw.yml";
my $merge_file  = "data/probe_data_cmb.yml";
my $star_file   = "data/stars.csv";
my $help = 0;

GetOptions(
  'help'     => \$help,
  'import=s' => \$import_file,
  'merge=s'  => \$merge_file,
  'stars=s'  => \$star_file,
);

  usage() if $help;

  
  my $import = YAML::XS::LoadFile($import_file);
  my $merged = YAML::XS::LoadFile($merge_file);

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

  my $fh;
  open($fh, ">", "$merge_file") || die "Could not open $merge_file";

  YAML::XS::DumpFile($fh, \@merged);
  close($fh);
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
  if ($orig->{type} ne $data->{type}) {
# We probably have a new space station to account for
    printf "Changing type of %s from %s:%s to %s:%s\n",
             $data->{name}, $orig->{image}, $orig->{type},
             $data->{image}, $data->{type};
    $orig = copy_body($orig, $data);
  }
  return $orig;
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
  if ($elem->{star_name} ne $stars->{$elem->{star_id}}->{name}) {
    $elem->{star_name} = $stars->{$elem->{star_id}}->{name};
  }
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
  --import <file>        - File to import, default: data/probe_data_raw.yml
  --merge  <file>        - Main file to merge into, default: data/probe_data_cmb.yml

END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
