use strict;
use warnings;

use Test::More tests => 3;
use List::MoreUtils qw'none uniq';
use YAML qw'LoadFile';

use FindBin;

my @type = keys %{ LoadFile "${FindBin::Bin}/../data/building.yml" };

ok scalar @type, 'Make sure there is data in data/building.yml';

our (@load,@simple);

use Games::Lacuna::Client::Buildings;
use Games::Lacuna::Client::Buildings::Simple;
{ no strict 'refs';
*load   = *{'Games::Lacuna::Client::Buildings::BuildingTypes'};
*simple = *{'Games::Lacuna::Client::Buildings::Simple::BuildingTypes'};
}

# don't worry about overlap, that is tested elsewhere
my @uniq = uniq @load, @simple;

{
  my @fail;
  for my $building( @type ){
    if( none { $building eq $_ } @uniq ){
      push @fail, $building
    }
  }
  ok !@fail, 'Check for buildings that are not loaded';
  if( @fail ){
    diag q[these aren't loaded anywhere];
    diag '  ', $_ for sort @fail;
  }
}

{
  my @fail;
  for my $building( @uniq ){
    if( none { $building eq $_ } @type ){
      push @fail, $building
    }
  }
  ok !@fail, q[Check for buildings that don't have any type information];
  if( @fail ){
    diag q[    These buildings don't have any type information:];
    diag '      ', $_ for sort @fail;
    diag '    Add these to data/building.yml';
    diag '    Then run data/sort_types.pl and data/build_types.pl';
  }
}
