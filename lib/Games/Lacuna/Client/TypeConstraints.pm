package Games::Lacuna::Client::TypeConstraints;

use List::MoreUtils qw'any';
use Games::Lacuna::Client::Types ':is';

use MooseX::Types::Moose qw'Str';

use MooseX::Types -declare => [qw(
  Resource ResourceType
  Food Ore Water Energy Waste
  Sellable
)];

subtype Food, (
  as Str,
  where { is_food_type($_) },
);

subtype Ore, (
  as Str,
  where { is_ore_type($_) },
);
 
subtype Water, (
  as Str,
  where {  $_ eq 'water' },
);

subtype Energy, (
  as Str,
  where { $_ eq 'energy' },
);

subtype Waste, (
  as Str,
  where { $_ eq 'waste' },
);

subtype Resource, (
  as Food|Ore|Water|Energy|Waste,
);

subtype ResourceType, (
  as Str,
  where {
    my $check = $_;
    any { $check eq $_ } qw'food ore water energy waste';
  }
);

my @sell_able = qw'food ore water waste energy glyph prisoner ship plan';
subtype Sellable, (
  as Str,
  where {
    my $check = $_;
    any { $check eq $_ } @sell_able;
  }
);
1;
