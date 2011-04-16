package LoadBuilding;
use strict;
use warnings;

use YAML qw'LoadFile thaw';
use Scalar::Util qw'reftype blessed';

sub _load{
  my($input) = @_;
  if( ref $input ){
    if( reftype $input eq 'SCALAR' ){
      return thaw $$input;
    }
  }else{
    return LoadFile $input;
  }
}

sub Load{
  my($self,$config) = @_;
  my $class = blessed $self || $self;
  
  $self = bless {},$class unless ref $self;
  $self->{yaml} = _load($config);
  for my $data ( values %{$self->{yaml}} ){
    @{$data->{tags}} = sort @{ $data->{tags} };
  }
  $self
}

sub types{
  my($self) = @_;
  my %type;
  my $yaml = $self->{yaml};
  for my $building ( sort keys %$yaml ){
    my $type = $yaml->{$building}{type};
    push @{$type{$type}}, $building;
  }
  return \%type;
}

sub tags{
  my($self) = @_;
  my %tags;
  my $yaml = $self->{yaml};
  for my $building ( sort keys %$yaml ){
    my $tags = $yaml->{$building}{tags};
    push @{ $tags{$building} }, @$tags;
  }
  return \%tags;
}

sub tag_list{
  my($self) = @_;
  my %tags;
  my $yaml = $self->{yaml};
  for my $building ( sort keys %$yaml ){
    my $tags = $yaml->{$building}{tags};
    for my $tag ( @$tags ){
      $tags{$tag} = undef;
    }
  }
  my @tags = sort keys %tags;
  return @tags if wantarray;
  return \@tags;
}
1;
