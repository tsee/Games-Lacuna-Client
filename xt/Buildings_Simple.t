use strict;
use warnings;

use Test::More tests => 5;
our( $package, @simple );
BEGIN {
  $package = 'Games::Lacuna::Client::Buildings::Simple';
  use_ok( $package );
};
{ no strict 'refs';
*simple = *{$package.'::BuildingTypes'};
}

ok scalar @simple, 'Make sure there is a list of simple buildings';

use List::MoreUtils qw'any uniq';

# beach9 comes before beach10
# Lagoon comes before LCOTA
sub mixed_sort{
  map {
    $_->[2]
  } sort {
    $a->[0] cmp $b->[0] || $a->[1] <=> $a->[1]
  } map {
    my ($l,$n) = /([a-z]*)(\d*)/i;
    [ lc($l), $n, $_ ]
  } @_
}

my @sorted = mixed_sort @simple;
is_deeply \@simple, \@sorted, 'Check if simple list is sorted';
is_deeply \@sorted, [uniq @sorted], 'Look for duplicates in simple list';

{
  use FindBin;
  use File::Spec::Functions qw'catdir updir';

  my $dir_name = catdir $FindBin::Bin, updir, 'lib', do{
    my @arr = split /::/, $package;
    pop @arr;
    @arr
  };

  my @fail;

  opendir my($dir_h), $dir_name;
  for my $file( readdir $dir_h ){
    next unless $file =~ /(.*)[.]pm$/;
    my $p = $1;
    if( any { $p eq $_ } @simple ){
      push @fail, $p;
    }
  }
  closedir $dir_h;

  ok !@fail, 'Check for modules in ::Buildings::Simple and in their own file';
  if( @fail ){
    diag 'Found:';
    diag '  ', $_ for sort @fail;
  }
}
