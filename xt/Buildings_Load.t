use strict;
use warnings;

use Test::More tests => 5;
our( $package, @load );
BEGIN {
  $package = 'Games::Lacuna::Client::Buildings';
  use_ok( $package );
};
{ no strict 'refs';
*load = *{$package.'::BuildingTypes'};
}

ok scalar @load, 'Make sure there is a list of buildings to load';

use List::MoreUtils qw'uniq none';

my @sorted = sort { lc $a cmp lc $b } @load;
is_deeply \@load, \@sorted, 'Check if simple list is sorted';
is_deeply \@sorted, [uniq @sorted], 'Look for duplicates in simple list';

{
  use FindBin;
  use File::Spec::Functions qw'catdir updir';

  my $dir_name = catdir $FindBin::Bin, updir, 'lib', split /::/, $package;

  my @skip = 'Modules';

  my @fail;

  opendir my($dir_h), $dir_name;
  for my $file( readdir $dir_h ){
    next unless $file =~ /(.*)[.]pm$/;
    next if $file eq 'Simple.pm';

    my $p = $1;
    if( none { $p eq $_ } @load, @skip ){
      push @fail, $p;
    }
  }
  closedir $dir_h;

  ok !@fail, 'Make sure that ::Buildings is loading all of the special buildings';
  if( @fail ){
    diag 'fails to load:';
    diag '  ', $_ for sort @fail;
  }
}
