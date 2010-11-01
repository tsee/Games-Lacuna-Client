#!/usr/bin/perl
#
use strict;
use warnings;
use Games::Lacuna::Client;
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

my @spaceports;

foreach my $planet (values %planets_by_name) {
  my %buildings = %{ $planet->get_buildings->{buildings} };

  my @b = grep {$buildings{$_}{name} eq 'Space Port'}
                  keys %buildings;
  push @spaceports, map  { $client->building(type => 'SpacePort', id => $_) } @b;
}

foreach my $sp (@spaceports) {
  my $ships=$sp->view_ships_travelling();
  my @ships=@{$ships->{ships_travelling}};
  foreach my $ship (@ships) {
    my $from=$ship->{from};
    my $to=$ship->{to};
    die unless ref($from) eq 'HASH';
    die unless ref($to) eq 'HASH';
    print $ship->{type_human},'  from ',$from->{name},' to ',$to->{name},"\n";
  }
}
