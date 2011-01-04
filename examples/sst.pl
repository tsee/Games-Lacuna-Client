#!/usr/bin/perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use YAML;
use YAML::Dumper;

print "Modify program to just look at the right planet and modify the trade variable\n";
exit;

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

my $embassy_file = "data/data_sst.yml";
GetOptions(
  'o=s' => \$embassy_file,
);
  
  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(OUTPUT, ">", "$embassy_file") || die "Could not open $embassy_file";

  my $data = $client->empire->view_species_stats();

# Get planets
  my $planets        = $data->{status}->{empire}->{planets};
  my $home_planet_id = $data->{status}->{empire}->{home_planet_id}; 

# Get Embassies
  my @embassy;
  for my $pid (keys %$planets) {
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    my $planet_name = $client->body(id => $pid)->get_status()->{body}->{name};
    next if ($planet_name ne "PLANET");

    my @sybit = grep { $buildings->{$_}->{url} eq '/transporter' } keys %$buildings;
    
    if (@sybit) { print "SST on $planet_name\n"; }
    push @embassy, @sybit;
  }

  print "SST IDs: ".join(q{, },@embassy)."\n";

# Find embassy
  my @builds;
  my $em_bit;
  my $trade = [ { "type" => "prisoner" , "prisoner_id" => "13286" },
                { "type" => "prisoner" , "prisoner_id" => "13287" },
                { "type" => "prisoner" , "prisoner_id" => "13288" },
                { "type" => "prisoner" , "prisoner_id" => "13289" },
              ];
  my $asking = 20;
  for my $sy_id (@embassy) {
    $em_bit = $client->building( id => $sy_id, type => 'Transporter' )->add_to_market($trade, $asking);
    push @builds, $em_bit;
  }

print OUTPUT $dumper->dump(\@builds);
close(OUTPUT);

