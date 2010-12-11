#!/usr/bin/perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Date::Parse;
use Date::Format;
use List::Util (qw(first));
use Getopt::Long          (qw(GetOptions));

my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
);

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
                      grep { $planet_name ? $planet_name eq $_ : 1 }
                      keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'

my @spaceports;

foreach my $planet (values %planets_by_name) {
  my %buildings = %{ $planet->get_buildings->{buildings} };

  my @b = first {$buildings{$_}{name} eq 'Space Port'}
                  keys %buildings;
  push @spaceports, map  { $client->building(type => 'SpacePort', id => $_) } @b;
}

my @ships;
foreach my $sp (@spaceports) {
  my $ships=$sp->view_ships_travelling();
  foreach my $ship ( @{$ships->{ships_travelling}} ) {
    ( my $date_arrives = $ship->{date_arrives} ) =~ s{^(\d+)\s+(\d+)\s+}{$2/$1/};
    $ship->{date_arrives} = str2time($date_arrives);
    push @ships, $ship;
  }
}

my $by_arrival = sub { $a->{date_arrives} <=> $b->{date_arrives} };

foreach my $ship (sort $by_arrival @ships) {
  my $from=$ship->{from};
  my $to=$ship->{to};
  my $arrives = time2str('%Y/%m/%d %H:%M', $ship->{date_arrives});
  #my $hours = int( ( $ship->{date_arrives} - time() ) / 3600 );
  my $hours = ( $ship->{date_arrives} - time() ) / 3600;
  if ($hours >= 2) {
      $hours = int $hours if $hours >= 2;
  } else {
      $hours = sprintf "%.1f", $hours;
  }
  die unless ref($from) eq 'HASH';
  die unless ref($to) eq 'HASH';
  print $ship->{type_human},' from ',$from->{name},' to ',$to->{name}," arrives in $hours hours ($arrives)\n";
}
