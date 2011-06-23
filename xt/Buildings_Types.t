use strict;
use warnings;

use Test::More tests => 4;
use List::MoreUtils qw'none uniq';
use YAML qw'LoadFile';

use FindBin;

my $data = LoadFile "${FindBin::Bin}/../data/building.yml";
my @type = keys %$data;

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
    build_diag();
    commit_diag();
  }
}

{
  my @fail;
  for my $building( @uniq ){
    unless( $data->{$building}{label} ){
      push @fail, $building;
    }
  }
  ok !@fail, q[Check for buildings that don't have a label];
  if( @fail ){
    diag q[    These buildings don't have a label:];
    diag '      ', $_ for sort @fail;
    diag '    Add a label for each in data/building.yml';
    build_diag();
    commit_diag();
  }
}

sub build_diag{
  diag '    Run data/sort_types.pl and data/build_types.pl';
}
sub commit_diag{
  diag '    If you are satisfied with the result, run the following commands';
  diag '      git add data/building.yml lib/Games/Lacuna/Client/Types.pm';
  diag '      git commit';
}
