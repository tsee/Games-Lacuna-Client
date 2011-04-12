package Games::Lacuna::Client::Market::Trade::Item;

sub new{
  my($class,$item) = @_;

  my $self = \$item;
  if( $item =~ /^(.*?)\s+\(.*?\)$/ ){
    bless $self, 'Games::Lacuna::Client::Market::Trade::Ship';
  }elsif( $item =~ /\bglyph$/ ){
    bless $self, 'Games::Lacuna::Client::Market::Trade::Glyph';
  }elsif( $item =~ /\bplan$/ ){
    bless $self, 'Games::Lacuna::Client::Market::Trade::Plan';
  }else{
    bless $self, 'Games::Lacuna::Client::Market::Trade::SimpleItem';
  }
  return $self;
}

{
  package Games::Lacuna::Client::Market::Trade::SimpleItem;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::Item';
  use Games::Lacuna::Client::Types ':list';
  use List::MoreUtils qw'any';

  sub type{
    my($self) = @_;
    my $type;
    if( ($type) = $$self =~ m(\s(\w+)$) ){
      if( any { $_ eq $type } food_types() ){
        return 'food';
      }elsif( any { $_ eq $type } ore_types() ){
        return 'ore';
      }elsif( any { $_ eq $type } qw'waste water energy' ){
        return $type;
      }
    }
    if( $$self =~ /prisoner/ ){
      return 'prisoner';
    }

    return;
  }

  sub sub_type{
    my($self) = @_;
    my($type) = $$self =~ / (.*)$/;
  }

  sub size{
    my($self) = @_;
    my($amount) = $$self =~ /(.*)\s/;
    $amount =~ s/,//;
    return $amount;
  }

  sub quantity{
    my($self) = @_;
    return $self->size;
  }

  sub desc{
    my($self) = @_;
    return $$self;
  }
}
{
  package Games::Lacuna::Client::Market::Trade::Plan;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';
  use Games::Lacuna::Client::Types ':meta';

  sub type{ 'plan' }
  sub size{ 10_000 }
  sub quantity{ 1 }

  sub plan_type{
    my($self) = @_;
    my($name) = $$self =~ /^(.*?) \(/;
    return meta_type($name);
  }
  sub sub_type{ plan_type(@_) }
  sub level{
    my($self) = @_;
    my($level) = $$self =~ /\((\d*[+]?\d*)\)/;
    return $level || 1;
  }
}
{
  package Games::Lacuna::Client::Market::Trade::Glyph;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';

  sub type{ 'glyph' }
  sub size{ 100 }
  sub quantity{ 1 }
  sub sub_type{
    my($self) = @_;
    my($type) = $$self =~ /^(.*) glyph$/;
    return $type;
  }
}
{
  package Games::Lacuna::Client::Market::Trade::Ship;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';

  sub type{ 'ship' }
  sub size{ 50_000 }
  sub quantity{ 1 }

  sub ship_type{
    my($self) = @_;
    my($type) = $$self =~ /^([^\(]+?) \(.*\)/;
    return $type;
  }
  sub sub_type{ ship_type(@_) }

  sub info{
    my($self) = @_;
    my($data) = $$self =~ /\((.*)\)/;

    my %data = split /[,:] /, $data;
    s/,// for values %data;

    return %data if wantarray;
    return \%data;
  }
  sub speed{
    my($self) = @_;
    return $self->info->{speed}
  }
  sub stealth{
    my($self) = @_;
    return $self->info->{stealth}
  }
  sub hold_size{
    my($self) = @_;
    return $self->info->{'hold size'}
  }
  sub combat{
    my($self) = @_;
    return $self->info->{combat}
  }
}
1;
