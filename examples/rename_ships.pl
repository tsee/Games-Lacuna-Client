#!/usr/bin/perl

use strict;
use warnings;

use List::Util            qw(min max);
use List::MoreUtils       qw(any none);
use Getopt::Long          qw(GetOptions);

use FindBin;
use lib "${FindBin::Bin}/../lib";

use Games::Lacuna::Client;

my $ships_per_page;
my %opts = (
  format => '${type} &{int(cargo/1000)||q[]}'
);

GetOptions(
  \%opts,
  'planet=s',
  'format=s',
  'dry-run|n!',
  'type=s@',
  'skip|s=s@',
);

# allow users to select groups of ship types
my %meta_type = (
  CARGO => [qw'dory cargo_ship barge freighter galleon hulk smuggler_ship'],
  BATTLE => [qw'fighter drone sweeper snark'],
);

if( $opts{type} ){
  my %type = map{ $_, undef } @{ $opts{type} };
  my @type;
  for my $meta ( keys %meta_type ){
    if( exists $type{$meta} ){
      delete $type{$meta};
      push @type, @{ $meta_type{$meta} };
    }
  }
  push @type, keys %type;
  $opts{type} = \@type;
}

# find config file
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

# load client
my $client = Games::Lacuna::Client->new(
  cfg_file => $cfg_file,
);

my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

while( my($name,$id) = each %planets ){
  # only work on one planet if asked to
  next if defined $opts{planet} && $opts{planet} ne $name;

  # Load planet data
  my $planet    = $client->body( id => $id );
  my $result    = $planet->get_buildings;
  my $body      = $result->{status}->{body};
  
  my $buildings = $result->{buildings};

  # Find the first Space Port
  my $space_port_id = List::Util::first {
    $buildings->{$_}->{name} eq 'Space Port'
  } keys %$buildings;
  
  next unless $space_port_id;
  
  my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );
  
  my $ship_count;
  my $page = 1;
  my @ships;
  
  do{
    my $return = $space_port->view_all_ships( $page++ );
    $ship_count = $return->{number_of_ships};
    push @ships, @{ $return->{ships} };
  } while ( @ships < $ship_count );
  
  if( $opts{type} ){
    @ships = grep {
      my $ship = $_;
      any { $ship->{type} eq $_ } @{ $opts{type} };
    } @ships;
  }
  
  for my $ship ( @ships ){
    my $name = $ship->{name};
    if(
      none {
        index( $name, $_ ) >= 0
      } @{ $opts{skip} }
    ){
      my $new_name = do_format($ship,$opts{format});
      if( $new_name eq $name ){
	print "'$name'\n";
      }else{
	print "'$name'\t'$new_name'\n";
	unless( $opts{'dry-run'} ){
	  $space_port->name_ship($ship->{id},$new_name);
	}
      }
    }else{
      print "#'$name'\n";
    }
  }
}

our(%alias,%type_l);

BEGIN{
  %alias = qw{
    cargo hold_size
  };
  %type_l = (
    1 => {qw{
      freighter     F
      barge         B
      cargo_ship    C
      galleon       G
      hulk          H
      dory          D
      smuggler_ship S
      drone         d
    }},
    2 => {qw{
      freighter     Fr
      barge         Bg
      cargo_ship    Cg
      hulk          Hk
      dory          Dy
    }},
    3 => {qw{
      freighter     Frt
      barge         Brg
      hulk          Huk
      dory          Dry
      smuggler_ship Smg
      drone         drn
    }},
    7 => {qw{
      cargo_ship    Cargo
    }},
  );
}

sub do_replace{
  my($str,$ship) = @_;

  my $key_match = do{
    local $" = '|';
    qr"@{[keys %$ship]}";
  };

  $str =~ s(
    type [(] (\d+) [)]
  ){
    $type_l{$1}{ $ship->{type} }
    ||
    substr( $ship->{type_human}, 0, $1 )
  }xge;
  $str =~ s/\b($key_match)\b/$ship->{$1}/ge;
  return $str;
}

sub do_format{
  my($ship,$format) = @_;
  my @stream = split /([\$&]\{[^{}]*\})/, $format;

  while( my($new,$old) = each %alias ){
    $ship->{$new} = $ship->{$old};
  }
  
  my $name = '';
  
  for my $elem (@stream){
    if( $elem =~ s/^\$\{([^{}]*)\}$/$1/ ){
      $elem = do_replace($elem,$ship);
    }elsif( $elem =~ s/^\&\{([^{}]*)\}$/$1/ ){
      $elem = do_replace($elem,$ship);
      $elem = eval $elem;
    }
    $name .= $elem if defined $elem;
  }
  return $name;
}
