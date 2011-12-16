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
use List::MoreUtils       qw( none );
use Getopt::Long          (qw(GetOptions));

my @planets;
my $ships_per_page = 25;

GetOptions(
    'planet=s' => \@planets,
);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my @spaceports;

foreach my $name ( sort keys %planets ) {

  next if @planets && none { lc $name eq lc $_ } @planets;

  # Load planet data
  my $planet    = $client->body( id => $planets{$name} );
  my $buildings = $planet->get_buildings->{buildings};

  my $id = first {
    $buildings->{$_}{name} eq 'Space Port'
  } keys %$buildings;

  next if !$id;

  push @spaceports, $client->building( id => $id, type => 'SpacePort' );
}

my @ships;
foreach my $sp (@spaceports) {
  my $ships = $sp->view_all_ships(
    {
      no_paging => 1,
    },
    {
      task => 'Travelling',
    }
  )->{ships};

  foreach my $ship ( @$ships ) {
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
