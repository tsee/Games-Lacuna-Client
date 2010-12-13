#!/usr/bin/perl
#
# Just a proof of concept for theme park

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $dump_file = "data_theme.yml";
GetOptions(
  'o=s' => \$dump_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$dump_file") || die "Could not open $dump_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Theme Park
  my @theme;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next unless ($planet_name eq "Reykjavik"); # Test Planet
    print "$planet_name\n";

    my @sybit = grep { $buildings->{$_}->{url} eq '/themepark' } keys %$buildings;
    if (@sybit) {
      print "Theme Park!\n";
    }
    print OUTPUT $dumper->dump(\@sybit);
    push @theme, @sybit;
  }

  print "Storage: ".join(q{, },@theme)."\n";

  my @builds;
  my $em_bit;
  for my $sy_id (@theme) {
    print "Lets ride the Bargletron\n";
#    $em_bit = $client->building( id => $sy_id, type => 'ThemePark' )->view();
    $em_bit = $client->building( id => $sy_id, type => 'ThemePark' )->operate();
    push @builds, $em_bit;
  }

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

