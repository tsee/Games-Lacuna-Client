package Games::Lacuna::Client::Market::TypeConstraints;

use MooseX::Types::Moose qw'ArrayRef Str';
use MooseX::Types -declare => [qw(
  TradeItem
  TradeItems
)];

subtype TradeItem, (
  as 'Games::Lacuna::Client::Market::Trade::Item',
);

subtype TradeItems, (
  as ArrayRef[TradeItem],
);

coerce TradeItem, (
  from Str,
  via {
    require Games::Lacuna::Client::Market::Trade::Item;
    Games::Lacuna::Client::Market::Trade::Item->new($_);
  },
);

coerce TradeItems, (
  from ArrayRef[Str],
  via {
    require Games::Lacuna::Client::Market::Trade::Item;
    [map{
      Games::Lacuna::Client::Market::Trade::Item->new($_)
    } @$_];
  },
);
