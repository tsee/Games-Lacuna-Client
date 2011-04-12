package Games::Lacuna::Client::Market::Trade;
use Scalar::Util qw'blessed';

use MooseX::Types::Moose qw'Str Int Num ArrayRef';
use Games::Lacuna::Client::Market::TypeConstraints 'TradeItems';

use namespace::clean;
use Moose;

has type => (
  is => 'ro',
  isa => Str, # Trade or Transporter
);
has ask => (
  is => 'ro',
  isa => Num,
);
sub price{
  my($self) = @_;
  return $self->ask;
}
has cost => (
  # Asking price plus Transporter "tax"
  is => 'ro',
  isa => Num,
  init_arg => undef,
  lazy => 1,
  default => sub {
    my($self) = @_;
    my $cost = $self->ask;
    if( $self->type eq 'Transporter' ){
      $cost++;
    }
    return $cost;
  },
);

has offer => (
  is => 'ro',
  isa => TradeItems,
  auto_deref => 1,
  coerce => 1,
);
has size => (
  is => 'ro',
  isa => Int,
  init_arg => undef,
  lazy => 1,
  default => sub{
    my($self) = @_;
    my $size = 0;
    for my $offer ( $self->offer ){
      $size += $offer->size;
    }
    return $size;
  },
);
has empire => (
  is => 'ro',
  isa => Str,
  init_arg => undef,
);
has empire_id => (
  is => 'ro',
  isa => Int,
  init_arg => undef,
);
sub BUILD{
  my($self,$args) = @_;
  my $empire = $args->{empire};
  $self->{empire} = $empire->{name};
  $self->{empire_id} = $empire->{id};
}

no Moose;
__PACKAGE__->meta->make_immutable;
