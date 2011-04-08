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
my $ships_per_page = 25;

GetOptions(
    'planet=s' => \$planet_name,
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
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

my @spaceports;

foreach my $name ( sort keys %planets ) {
  next if defined $planet_name && $planet_name ne $name;
  
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
  my $ships = [];
  my $page  = 1;
  my $response;
  
  do {
    $response = $sp->view_ships_travelling( $page++ );
    
    push @$ships, @{ $response->{ships_travelling} };
    
  } while ( @$ships < $response->{number_of_ships_travelling} );
  
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
