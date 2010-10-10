package LacunaMap::DB;
use strict;
use warnings;
use 5.10.0;
require ORLite;

my $initialized = 0;
sub import {
  my $class = shift;
  my $file = shift;
  return if not defined $file;
  $initialized = 1;

  ORLite->import({
    file         => $file,
    package      => 'LacunaMap::DB',
    create       => sub {
      my $dbh = shift;
      $dbh->do(<<'HERE');
        CREATE TABLE stars (
          id INT PRIMARY KEY,
          name TEXT,
          x INT NOT NULL,
          y INT NOT NULL,
          color TEXT,
          zone TEXT
        );
HERE
      $dbh->do(<<'HERE');
        CREATE TABLE bodies (
          id INT PRIMARY KEY,
          name TEXT,
          x INT NOT NULL,
          y INT NOT NULL,
          star_id INT NOT NULL,
          orbit INT NOT NULL,
          type TEXT,
          size INT NOT NULL,
          water INT,
          empire_id INT
        );
HERE
    # todo ore-body table
    },
    tables       => [ qw(stars bodies) ],
    #cleanup      => 'VACUUM',
    @_
  });
}

package LacunaMap::DB::Stars;
sub min_x {
  my $row = LacunaMap::DB->selectrow_arrayref("SELECT MIN(x) FROM stars");
  ref($row) && ref($row) eq 'ARRAY' && @$row > 0 && defined($row->[0])
    or die "Is the stars database empty? Did you load a database?";
  return $row->[0];
}

sub max_x {
  my $row = LacunaMap::DB->selectrow_arrayref("SELECT MAX(x) FROM stars");
  ref($row) && ref($row) eq 'ARRAY' && @$row > 0 && defined($row->[0])
    or die "Is the stars database empty? Did you load a database?";
  return $row->[0];
}

sub min_y {
  my $row = LacunaMap::DB->selectrow_arrayref("SELECT MIN(y) FROM stars");
  ref($row) && ref($row) eq 'ARRAY' && @$row > 0 && defined($row->[0])
    or die "Is the stars database empty? Did you load a database?";
  return $row->[0];
}

sub max_y {
  my $row = LacunaMap::DB->selectrow_arrayref("SELECT MAX(y) FROM stars");
  ref($row) && ref($row) eq 'ARRAY' && @$row > 0 && defined($row->[0])
    or die "Is the stars database empty? Did you load a database?";
  return $row->[0];
}

1;
