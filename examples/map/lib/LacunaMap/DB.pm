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
      # NOTE: body doesn't have a primary key because the id isn't necessarily known
      $dbh->do(<<'HERE');
        CREATE TABLE bodies (
          sql_primary_id INTEGER PRIMARY KEY AUTOINCREMENT,
          id INT UNIQUE,
          name TEXT,
          x INT,
          y INT,
          star_id INT NOT NULL,
          orbit INT,
          type TEXT,
          size INT,
          water INT,
          empire_id INT
        );
HERE
      $dbh->do(<<'HERE');
        CREATE TABLE news (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          zone TEXT,
          title TEXT,
          time TIMESTAMP
        );
HERE
    # todo ore-body table
    },
    tables       => [ qw(stars bodies news) ],
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


package LacunaMap::DB::Bodies;

sub update_from_news {
  my $class = shift;
  my $client = shift;
  my $news = shift;

  my $updater = sub {
    my $news = $_;
    my $res = $news->parse_title;
    return if not $res;
    if ($res->{type} eq 'new colony') {
      warn "NEW COLONY";
        use Data::Dumper;
        warn Dumper $res;

      my $stars = LacunaMap::DB::Stars->select(
        'where name = ?', $res->{star_name}
      );
      if (@$stars > 1) {
        warn "Found multiple stars for the given new colony";
        return;
      }
      elsif (@$stars == 0) {
        warn "Found no star for the given new colony";
        return;
      }
      my $sid = $stars->[0]->id;

      my $eid = _find_empire_id($client, $res->{empire_name});
      return if not defined $eid;

      my $bodies = LacunaMap::DB::Bodies->select(
        'where star_id = ? and name = ?', $sid, $res->{body_name}
      );
      if (not @$bodies) {
        # new entry
        LacunaMap::DB::Bodies->new(
          name      => $res->{body_name},
          empire_id => $eid,
          star_id   => $sid,
        )->insert;
      }
      elsif (@$bodies == 1) {
        for ($bodies->[0]) {
          $_->delete();
          $_->name($res->{body_name});
          $_->empire_id($res->{empire_id});
          $_->star_id($res->{star_id});
          $_->insert();
        }
      }
      else {
        warn "Found multiple bodies for the given new colony";
        return;
      }
    } # end if new colony
    elsif ($res->{type} eq 'rename') {
      my $bodies = LacunaMap::DB::Bodies->select('where name = ?', $res->{old_body_name});
      if ($bodies and @$bodies == 1) { # only rename if unique
        my $b = $bodies->[0];
        $b->delete;
        $b->name($res->{new_body_name});
        $b->insert;
      }
      # TODO: disambiguate body name by empire id!
    }
  };

  if (not $news) { # all
    LacunaMap::DB::News->iterate(
      'order by ?', 'time',
      $updater
    );
  }
  else {
    local $_ = $news;
    $updater->();
  }
}

sub _find_empire_id {
  my $client = shift;
  my $name = shift;
  my $res = $client->empire->find($name);
  return $res->{empires}[0]{id};
}

package LacunaMap::DB::News;

sub parse_title {
  my $self = shift;
  my $title = $self->title;
  my $rv;
  if ($title =~ /^(.+)\s+founded a new colony on (.+)\.\s*$/) {
    my ($empire, $body) = ($1, $2);
    my $star = $body;
    $star =~ s/\s+\d+$//;
    $rv = {type => 'new colony', empire_name => $empire, body_name => $body, star_name => $star};
  }
  elsif ($title =~ /^In a bold move to show its growing power, (.*) renamed (.*) to (.*)\.$/) { # uh, inefficient
    my ($empire, $old, $new) = ($1, $2, $3);
    $rv = {type => 'rename', empire_name => $empire, old_body_name => $old, new_body_name => $new};
  }
  return $rv;
}

1;
