#!/usr/bin/perl
#
# Script to parse thru missions
#
# Usage: perl parse_missions.pl mission_files
#
# Produces files of mission_name.yml
# If -b switch used, prints to STDOUT the entire list that can be redirected to one file.
# Seperate files are good for comparing while the big list is good for scanning thru
#  
use strict;
use warnings;
use JSON;
use YAML;
use YAML::Dumper;
use Getopt::Long qw(GetOptions);

my $bigfile = 0;
GetOptions(
  'big' => \$bigfile,
);

my $yaml_out;
my %mission_hash;
if ($bigfile) {
  $yaml_out = YAML::Dumper->new;
  $yaml_out->indent_width(4);
}

  
  my $filename;
  for $filename (@ARGV) {
    next unless -e $filename;
    my $nfile =  $filename.".yml";
    my $data = process_mission($filename);
    explode($nfile, $data);
    if ($bigfile) {
      $mission_hash{$filename} = $data;
    }
  }
  if ($bigfile) {
    print $yaml_out->dump(\%mission_hash);
  }

exit;

sub explode {
  my ($nfile, $data, $bigfile) = @_;
  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(EXP, ">", "$nfile") or die "Could not open $nfile!";
  print EXP $dumper->dump($data);
  close(EXP);
}

sub process_mission {
  my ($file) = @_;
  open(MISSION, "$file") or die "Bad mission file: $file\n";

  my @afile = <MISSION>;
  close(MISSION);
  return decode_json($afile[1]);
}
