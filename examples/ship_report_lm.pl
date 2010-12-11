#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Data::Dumper;

binmode STDOUT, ":utf8";

open(PLANET, ">planet_ships.csv") or die;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
                      keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'

printf PLANET "%s,%s,%s\n", "Planet","Max","Avail";
my @ships;
foreach my $planet (values %planets_by_name) {
  my %buildings = %{ $planet->get_buildings->{buildings} };

  my @b = grep {$buildings{$_}{name} eq 'Space Port'}
                  keys %buildings;
  my @spaceports;
  push @spaceports, map  { $client->building(type => 'SpacePort', id => $_) } @b;

  my $sp = $spaceports[0];
  my $bld_data = $sp->view();
  my $planet_name = $bld_data->{status}->{body}->{name};
  printf PLANET "%s,%d,%d\n",
               $planet_name, $bld_data->{max_ships}, $bld_data->{docks_available};
  my $pages = 1;
  my @ship_page;
  do {
    my $ships_ref = $sp->view_all_ships($pages++)->{ships};
    @ship_page = @{$ships_ref};
    if (@ship_page) {
      foreach my $ship ( @ship_page ) {
        $ship->{planet} = $planet_name;
        rename_ship($sp, $ship);
      }
      push @ships, @ship_page;
    }
  } until (@ship_page == 0)

}

printf "%s,%s,%s,%s,%s,%s,%s,%s\n", "Planet", "Type", "Task",
                   "Hold", "Speed", "Stealth", "Name","ID";
my @ship_ids;
foreach my $ship (sort byshipsort @ships) {
#  next if grep {/$ship->{id}/} @ship_ids;
  next if grep {$ship->{id} eq $_ } @ship_ids;
  push @ship_ids, $ship->{id};
  printf "%s,%s,%s,%d,%d,%d,%s,%d\n",
         $ship->{planet}, $ship->{type_human}, $ship->{task},
         $ship->{hold_size}, $ship->{speed}, $ship->{stealth},
         $ship->{name}, $ship->{id};
}

sub rename_ship {
  my ($sp, $ship) = @_;
  
  my $new_name = $ship->{name};
  if ($ship->{task} eq "Mining") {
    $new_name = "Miner ".$ship->{hold_size};
  }
  elsif ($ship->{type_human} eq "Cargo Ship") {
    $new_name = "Cargo ".$ship->{hold_size};
  }
  elsif ($ship->{type_human} eq "Freighter") {
    $new_name = "Freight ".$ship->{hold_size};
  }
  elsif ($ship->{type_human} eq "Smuggler Ship") {
    $new_name = "Stealth ".$ship->{hold_size};
  }
  elsif ($ship->{type_human} eq "Dory") {
    $new_name = "Dory ".$ship->{hold_size};
  }
  elsif ($ship->{type_human} eq "Snark") {
    $new_name = "Snark ".$ship->{speed};
  }
  elsif ($ship->{type_human} eq "Scanner") {
    $new_name = "Scan ".$ship->{speed};
  }
  elsif ($ship->{type_human} eq "Mining Platform Ship") {
    $new_name = "Platform Mining";
  }
  elsif ($ship->{type_human} eq "Terraforming Platform Ship") {
    $new_name = "Platform Terra";
  }
  elsif ($ship->{type_human} eq "Gas Giant Settlement Ship") {
    $new_name = "Platform Gas";
  }
  if ($new_name ne $ship->{name}) {
    $sp->name_ship($ship->{id}, $new_name);
    $ship->{name} = $new_name;
  }
}

sub byshipsort {
   $a->{planet} cmp $b->{planet} ||
    $a->{task} cmp $b->{task} ||
    $a->{type} cmp $b->{type} ||
    $b->{hold_size} <=> $a->{hold_size} ||
    $b->{speed} <=> $a->{speed} ||
    $a->{id} <=> $b->{id}; 
    
}

#  printf "%s %s %s %d %d %d %d %s %s\n",
#         $ship->{planet}, $ship->{name}, $ship->{task}, $ship->{stealth},
#         $ship->{speed}, $ship->{hold_size}, $ship->{id}, $ship->{type},
#         $ship->{type_human};
