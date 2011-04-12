package Games::Lacuna::Client::Market;
use strict;
use warnings;

use Games::Lacuna::Client;
use Scalar::Util qw'blessed';
use List::MoreUtils qw'any';

use MooseX::Types::Moose qw'Str Int';
use Games::Lacuna::Client::TypeConstraints qw'Sellable';

use Games::Lacuna::Client::Market::Trade;

use namespace::clean;
use Moose;

{
  my @filter = qw'food ore water waste energy glyph prisoner ship plan';
  sub _valid_filter{
    my($filter) = @_;
    return any { $_ eq $filter } @filter;
  }
}

has filter => (
  is => 'rw',
  isa => Sellable,
  predicate => 'has_filter',
);

has call_limit => (
  is => 'rw',
  isa => Int,
  default => 20,
);

has building => (
  is => 'rw',
  isa => Str,
);

has planet_id => (
  is => 'rw',
  isa => Int,
);

has planet_name => (
  is => 'rw',
  isa => Str,
);

has client => (
  is => 'ro',
  isa => 'Games::Lacuna::Client',
);

sub BUILD{
  my( $self, $args ) = @_;
  unless( $args->{client} ){
    $self->{client} = Games::Lacuna::Client->new(
      %$args
    );
  }
}

sub _search_for_building{
  my($self,$pid,$type) = @_;
  # $type should be Trade or Transporter
  $type = 'Trade' unless $type;
  $type = "/$type" unless substr($type, 0, 1) eq '/';
  $type = lc $type;

  my $buildings = $self->{client}->body(id => $pid)->get_buildings()->{buildings};

  for my $id ( keys %$buildings ){
    my $url = $buildings->{$id}{url};
    next unless $url eq $type;
    return $id;
  }

  return undef; # should this die instead?
}

sub available_trades{
  my($self,%arg) = @_;
  my $client = $self->{client};
  my $status = $client->empire->get_status();
  my $planets = $status->{empire}{planets};

  my $p_id;
  if( $arg{planet_name} and not $arg{planet_id} ){
    my $planet = $arg{planet_name};
    ($p_id) = grep { $planets->{$_} eq $planet } keys %$planets;
    die "Unable to find planet named '$planet'\n" unless defined $p_id;
  }elsif( $arg{planet_id} ){
    $p_id = $arg{planet_id};
  }

  my $type = $arg{building};
  # $type should be Trade or Transporter
  $type = 'Trade' unless $type;

  unless( $type eq 'Trade' or $type eq 'Transporter' ){
    die "Invalid trade building: $type\n"
  }

  my($class,%opt) = @_;
  $class = blessed $class || $class;

  my $b_id;

  if( defined $p_id ){
    $b_id = $self->_search_for_building($p_id,$type);
  }else{
    for $p_id ( keys %$planets ){
      $b_id = $self->_search_for_building($p_id,$type);
      last if defined $b_id;
    }
  }

  die "Unable to find appropriate building" unless defined $b_id;

  my $building = $client->building( id => $b_id, type => $type );
  my $filter = $arg{filter};
  my $page_num = 1;
  my $trades_per_page = 25;
  my $max_pages = $arg{call_limit} || 20;
  my @trades;

  while(
    my $result = $building->view_market($page_num, $filter)
  ){
    push @trades, map{
      Games::Lacuna::Client::Market::Trade->new( %$_, type => $type );
    } @{$result->{trades}};

    # stop if this is the last page
    last if $result->{trade_count} <= $page_num * $trades_per_page;
    # stop if the next page will be past the limit
    last if ++$page_num > $max_pages;
  }

  return @trades if wantarray;
  return \@trades;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
