#!/usr/bin/perl
#
# This program manages the star database used by glyphinator
# It performs the following functions:
#
#  * Fill star db from probe data
#  * Merge a second db into the main one

use strict;
use warnings;

use DBI;
use FindBin;
use List::Util qw(first);
use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);

use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;

my %opts;
GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'q|quiet',
    'config=s',
    'db=s',
    'create-db',
    'upgrade',
    'merge-db=s',
    'planet=s@',
    'no-fetch',
    'no-vacuum',
    'scan-nearby',
);

usage() if $opts{h};

my %do_planets;
if ($opts{planet}) {
    %do_planets = map { normalize_planet($_) => 1 } @{$opts{planet}};
}

my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "$FindBin::Bin/../lacuna.yml",
);

no warnings 'once';
my $db_file = $opts{db} || "$FindBin::Bin/../stars.db";
my $star_db;
if (-f $db_file) {
    $star_db = DBI->connect("dbi:SQLite:$db_file")
        or die "Can't open star database $db_file: $DBI::errstr\n";
    $star_db->{RaiseError} = 1;
    $star_db->{PrintError} = 0;

    if ($opts{'upgrade'}) {
        upgrade_star_db();
    } else {
        # Check if db is current, if not, suggest upgrade
        my $ok = eval {
            $star_db->do('select subtype from orbitals limit 1');
            return 1;
        };
        unless ($ok) {
            die "Database is outdated, please specify --upgrade to continue\n";
        }
    }
} else {
    if ($opts{'create-db'}) {
        $star_db = DBI->connect("dbi:SQLite:$db_file")
            or die "Can't create star database $db_file: $DBI::errstr\n";
        $star_db->{RaiseError} = 1;
        $star_db->{PrintError} = 0;

        for my $sql (create_star_db_sql()) {
            $star_db->do($sql);
        }
        output("$db_file initialized\n");
    } else {
        die "No star database found.  Specify it with --db or use --create-db to create it.\n";
    }
}
$star_db->{AutoCommit} = 0;

if ($opts{'merge-db'}) {
    unless (-f $opts{'merge-db'}) {
        die "Can't locate database to merge: $opts{'merge-db'}\n";
    }
    $star_db->{AutoCommit} = 1;
    $star_db->do('attach database ? as d2', {}, $opts{'merge-db'});
    $star_db->{AutoCommit} = 0;

    # Copy stars
    my $get_stars;
    my $ok = eval {
        $get_stars = $star_db->prepare(<<SQL);
select s2.*, strftime('%s', s2.last_checked) checked_epoch
from d2.stars s2
join stars s1 on s1.id = s2.id
    and coalesce(s2.last_checked, 0) >= coalesce(s1.last_checked,0)
SQL
        $get_stars->execute;
        return 1;
    };
    unless ($ok) {
        my $e = $@;
        if ($e =~ /no such column/) {
            output("$opts{'merge-db'} is outdated, it should be upgraded and re-fetched\n");
            $get_stars = $star_db->prepare(q{select *, 0 checked_epoch from d2.stars});
            $get_stars->execute;

        } else {
            die $e;
        }
    }
    while (my $star = $get_stars->fetchrow_hashref) {
        if (my $row = star_exists($star->{x}, $star->{y})) {
            if (($star->{checked_epoch}||0) >= ($row->{checked_epoch}||0)) {
                update_star($star)
            }
        } else {
            insert_star($star);
        }
    }

    # Copy orbitals
    my $get_orbitals;
    $ok = eval {
        $get_orbitals = $star_db->prepare(<<SQL);
select o2.*, strftime('%s', o2.last_checked) checked_epoch
from d2.orbitals o2
join orbitals o1 on o1.star_id = o2.star_id
    and o1.orbit = o2.orbit
    and coalesce(o2.last_checked, 0) >= coalesce(o1.last_checked,0)
SQL
        $get_orbitals->execute;
        return 1;
    };
    unless ($ok) {
        my $e = $@;
        if ($e =~ /no such column/) {
            output("$opts{'merge-db'} is outdated, it should be upgraded and re-fetched\n");
            $get_orbitals = $star_db->prepare(q{select *, 0 checked_epoch from d2.orbitals});
            $get_orbitals->execute;

        } else {
            die $e;
        }
    }
    while (my $orbital = $get_orbitals->fetchrow_hashref) {
        # Check if it exists in the star db, and if so what its type is
        if (my $row = orbital_exists($orbital->{x}, $orbital->{y})) {
            if (($orbital->{checked_epoch}||0) >= ($row->{checked_epoch}||0)) {
                update_orbital( {
                    empire => { id => $orbital->{empire_id} },
                    (map { $_ => $orbital->{$_} } qw/x y type name water size/),
                    ore => { map { $_ => $orbital->{$_} } ore_types() },
                    last_checked => $orbital->{last_checked},
                    image => $orbital->{subtype},
                } );
            }
        } else {
            insert_orbital( {
                empire => { id =>  $orbital->{empire_id} },
                (map { $_ => $orbital->{$_} } qw/body_id star_id orbit x y type name water size/),
                ore => { map { $_ => $orbital->{$_} } ore_types() },
                last_checked => $orbital->{last_checked},
                image => $orbital->{subtype},
            } );
        }
    }

    $ok = eval {
        my $get_empires = $star_db->prepare('select * from d2.empires');
        $get_empires->execute;
        while (my $empire = $get_empires->fetchrow_hashref) {
            update_empire($empire);
        }
        return 1;
    };
    unless ($ok) {
        my $e = $@;
        if ($e =~ /no such table/) {
            output("$opts{'merge-db'} is outdated, it should be upgraded and re-fetched\n");
        }
        else {
            die $e;
        }
    }

    output("$db_file synchronized with $opts{'merge-db'}\n");
}

unless ($opts{'no-fetch'}) {
    my $empire = $glc->empire->get_status->{empire};

    # reverse hash, to key by name instead of id
    my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};

    # Scan each planet
    for my $planet_name (keys %planets) {
        if (keys %do_planets) {
            next unless $do_planets{normalize_planet($planet_name)};
        }

        verbose("Inspecting $planet_name\n");

        # Load planet data
        my $planet    = $glc->body(id => $planets{$planet_name});
        my $result    = $planet->get_buildings;
        my $buildings = $result->{buildings};
        $planet = $result->{status}->{body};
        my @stars;

        my $obs = find_observatory($buildings);
        if ($obs) {
            my $page = 1;
            verbose("Getting page $page of probed stars...\n");
            my $probed_stars = $obs->get_probed_stars($page);
            push(@stars, @{ $probed_stars->{'stars'} });
            while ($probed_stars->{star_count} > $page * 25) {
                $page++;
                verbose("Getting page $page of probed stars...\n");
                $probed_stars = $obs->get_probed_stars($page);
                push(@stars, @{ $probed_stars->{'stars'} });
            }
        }

        if ( $opts{'scan-nearby'} ) {
            verbose("Getting scan of systems near $planet->{'name'} \n");
            my $sector_size = 30;
            my $map = $glc->map;

            my ($x, $y) = ($planet->{'x'}, $planet->{'y'});
            push(@stars, @{ $map->get_stars( $x - $sector_size, $y, $x, $y + $sector_size )->{'stars'} });
            push(@stars, @{ $map->get_stars( $x, $y, $x + $sector_size, $y + $sector_size )->{'stars'} });
            push(@stars, @{ $map->get_stars( $x - $sector_size, $y - $sector_size, $x, $y )->{'stars'} });
            push(@stars, @{ $map->get_stars( $x, $y - $sector_size, $x + $sector_size, $y )->{'stars'} });

        }

        my %seen;
        @stars = grep { ! $seen{$_->{'name'}}++ } @stars;

        for my $star (@stars) {
            if (my $row = star_exists($star->{x}, $star->{y})) {
                if ((($row->{name}||q{}) ne $star->{name})
                        or (($row->{color}||q{}) ne $star->{color})
                        or (($row->{zone}||q{}) ne $star->{zone})) {
                    update_star($star)
                } else {
                    mark_star_checked(@{$row}{qw/x y/});
                }
            } else {
                insert_star($star);
            }

            if ($star->{bodies} and @{$star->{bodies}}) {
                for my $body (@{$star->{bodies}}) {
                    if (my $row = orbital_exists($body->{x}, $body->{y})) {
                        if ((($row->{type}||q{}) ne $body->{type})
                                or (($row->{name}||q{}) ne $body->{name})
                                or ($body->{empire} and ($row->{empire_id}||q{}) ne $body->{empire}{id})
                                or (defined($body->{size}) and ($row->{size}||q{}) ne $body->{size}) ) {
                            update_orbital($body);
                        } else {
                            mark_orbital_checked(@{$body}{qw/x y/});
                        }
                    } else {
                        insert_orbital($body);
                    }
                }
            }
        }

    }
}

$star_db->commit;

# SQLite can't vacuum in a transaction
    unless ($opts{'no-vacuum'}) {
    verbose("Vacuuming database\n");
    $star_db->{AutoCommit} = 1;
    $star_db->do('vacuum');
}

unless ($opts{'no-fetch'}) {
    output("$db_file is now up-to-date with your probe data\n");
}

output("$glc->{total_calls} api calls made.\n") if $glc->{total_calls};
undef $glc;
exit 0;

sub ore_types {
    return qw{
            anthracite bauxite beryl chalcopyrite chromite fluorite galena goethite gold gypsum
            halite kerogen magnetite methane monazite rutile sulfur trona uraninite zircon
    };
}

{
    my $check_star;
    sub star_exists {
        my ($x, $y) = @_;
        $check_star ||= $star_db->prepare(q{select *, strftime('%s',last_checked) checked_epoch from stars where x = ? and y = ?});
        $check_star->execute($x, $y);
        my $row = $check_star->fetchrow_hashref;
        return $row;
    }
}

{
    my $insert_star;
    sub insert_star {
        my ($star) = @_;
        my ($id, $name, $x, $y, $color, $zone) = @{$star}{qw/id name x y color zone/};

        my $when = $star->{last_checked} || strftime "%Y-%m-%d %T", gmtime;

        output("Inserting star $name at $x, $y\n");
        $insert_star ||= $star_db->prepare('insert into stars (id, name, x, y, color, zone, last_checked) values (?,?,?,?,?,?,?)');
        $insert_star->execute($id, $name, $x, $y, $color, $zone, $when)
            or die "Can't insert star: " . $insert_star->errstr;
    }
}

{
    my $update_star;
    sub update_star {
        my ($star) = @_;
        my ($x, $y, $name, $color, $zone) = @{$star}{qw/x y name color zone/};

        my $when = $star->{last_checked} || strftime "%Y-%m-%d %T", gmtime;

        output("Updating star at $x, $y to name $name, color $color, zone $zone\n");
        $update_star ||= $star_db->prepare(q{update stars set last_checked = ?, name = ?, color = ?, zone = ? where x = ? and y = ?});
        $update_star->execute($when, $name, $color, $zone, $x, $y);
    }
}

{
    my $star_checked;
    sub mark_star_checked {
        my ($x, $y) = @_;
        $star_checked ||= $star_db->prepare(q{update stars set last_checked = datetime('now') where x = ? and y = ?});
        $star_checked->execute($x, $y)
            or die "Can't mark star checked: " . $star_checked->errstr;
    }
}

{
    my $check_orbital;
    sub orbital_exists {
        my ($x, $y) = @_;

        $check_orbital ||= $star_db->prepare(q{select *, strftime('%s',last_checked) checked_epoch from orbitals where x = ? and y = ?});
        $check_orbital->execute($x, $y);
        return $check_orbital->fetchrow_hashref;
    }
}

{
    my $insert_orbital;
    sub insert_orbital {
        my ($body) = @_;
        my @body_fields = qw{ body_id star_id orbit x y type name water size };
        output(sprintf  "Inserting %s at %d, %d\n", $body->{'type'}, $body->{'x'}, $body->{'y'});

        my $when = $body->{last_checked} || strftime "%Y-%m-%d %T", gmtime;

        my $insert_statement =
            q{insert into orbitals (last_checked, }
            . join(", ",
                @body_fields, ore_types(),
                'empire_id', 'subtype'
            )
            . ') values (?,'
            . join(',', map { "?" } @body_fields, ore_types(), 'empire_id', 'subtype')
            . ')';

        my $subtype;
        if (defined $body->{'image'}) {
            ($subtype = $body->{'image'}) =~ s/-.*//;
        }
        my @insert_vars = (
            $when,
            ( map { $body->{$_} } @body_fields ),
            ( map { $body->{'ore'}->{$_} } ore_types() ),
            $body->{'empire'}->{'id'},
            $subtype,
        );

        $insert_orbital ||= $star_db->prepare($insert_statement);
        $insert_orbital->execute(@insert_vars)
            or die( "Can't insert orbital: " . $insert_orbital->errstr);

        update_empire($body->{empire}) if $body->{empire} and $body->{empire}{name};
    }
}

{
    my $update_orbital;
    sub update_orbital {
        my ($body) = @_;

        my @body_fields = qw{ type name x y water size };
        output(sprintf  "Updating %s at %d, %d\n", $body->{'type'}, $body->{'x'}, $body->{'y'});

        my $when = $body->{last_checked} || strftime "%Y-%m-%d %T", gmtime;

        my $update_statement =
            join(", ",
                q{update orbitals set last_checked = ? },
                ( map { "$_ = ?" } @body_fields, ore_types() ),
                'empire_id = ?, subtype = ?'
            )
            . ' where x = ? and y = ?';

        my @update_vars = (
            $when,
            ( map { $body->{$_} } @body_fields ),
            ( map { $body->{'ore'}->{$_} } ore_types() ),
        );
        my $subtype;
        if (defined $body->{'image'}) {
            ($subtype = $body->{'image'}) =~ s/-.*//;
        }
        push( @update_vars, $body->{'empire'}->{'id'}, $subtype, $body->{'x'}, $body->{'y'} );
        $update_orbital ||= $star_db->prepare($update_statement);

        $update_orbital->execute(@update_vars)
            or die("Can't update orbital: " . $update_orbital->errstr);

        update_empire($body->{empire}) if $body->{empire} and $body->{empire}{name};
    }
}

sub update_empire {
    my $empire = shift;

    return unless defined $empire->{id};

    my $exists = $star_db->selectrow_hashref('select * from empires where id = ?', {}, $empire->{id});
    unless ($exists) {
        output("Inserting empire $empire->{name} ($empire->{id})\n");
        $star_db->do('insert into empires (id, name) values (?,?)', {}, $empire->{id}, $empire->{name});
    }
}

{
    my $orbital_checked;
    sub mark_orbital_checked {
        my ($x, $y) = @_;
        $orbital_checked ||= $star_db->prepare(q{update orbitals set last_checked = datetime('now') where x = ? and y = ?});
        $orbital_checked->execute($x, $y)
            or die "Can't mark orbital checked: " . $orbital_checked->errstr;
    }
}


sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub find_observatory {
    my ($buildings) = @_;

    # Find an Observatory
    my $obs_id = first {
            $buildings->{$_}->{name} eq 'Observatory'
    } keys %$buildings;

    return if not $obs_id;
    return $glc->building(id => $obs_id, type => 'Observatory');
}


sub create_star_db_sql {
    return
        <<SQL,
CREATE TABLE stars (
    id           int   primary key,
    name         text,
    x            int,
    y            int,
    color        text,
    zone         text,
    last_checked datetime
)
SQL
        <<SQL,
CREATE TABLE orbitals (
    body_id        int,
    star_id        int,
    orbit          int,
    x              int,
    y              int,
    type           text,
    subtype        text,
    last_excavated datetime,
    name           text,

    water          int,
    size           int,
    anthracite     int,
    bauxite        int,
    beryl          int,
    chalcopyrite   int,
    chromite       int,
    fluorite       int,
    galena         int,
    goethite       int,
    gold           int,
    gypsum         int,
    halite         int,
    kerogen        int,
    magnetite      int,
    methane        int,
    monazite       int,
    rutile         int,
    sulfur         int,
    trona          int,
    uraninite      int,
    zircon         int,

    empire_id      int,
    last_checked   datetime,
    PRIMARY KEY(star_id, orbit),
    FOREIGN KEY(star_id) REFERENCES stars(id)
)
SQL
        <<SQL,
CREATE TABLE empires (
    id int,
    name text
)
SQL
        <<SQL,
CREATE INDEX orbital_x_y on orbitals(x,y)
SQL
        <<SQL,
CREATE INDEX zone on stars(zone)
SQL
        <<SQL,
CREATE INDEX empire_id on empires(id)
SQL
}

sub upgrade_star_db {
    output("Performing upgrade...");
    my @tests = (
        [
            'select zone from stars limit 1',
            [
                'alter table stars add zone text',
                'create index zone on stars(zone)',
                q{update stars set zone = cast(x/250 as text) || '|' || cast(y/250 as text) where zone is null},
            ],
        ],
        [
            'select name from orbitals limit 1',
            ['alter table orbitals add name text'],
        ],
        [
            'select empire_id from orbitals limit 1',
            ['alter table orbitals add empire_id int'],
        ],
        [
            'select last_checked from orbitals limit 1',
            ['alter table orbitals add last_checked datetime'],
        ],
        [
            'select last_checked from stars limit 1',
            ['alter table stars add last_checked datetime'],
        ],
        [
            'select water from orbitals limit 1',
            [
                'alter table orbitals add water int',
                'alter table orbitals add size int',
                map { "alter table orbitals add $_ int" } ore_types(),
            ],
        ],
        [
            'select id from empires limit 1',
            [
                'create table empires (id int, name text)',
                'create index empire_id on empires(id)',
            ],
        ],
        [
            'select subtype from orbitals limit 1',
            [
                'alter table orbitals add subtype text',
            ],
        ],
    );

    check_and_upgrade(@$_) for @tests;
    output("done\n");
}

sub check_and_upgrade {
    my ($check, $upgrade_sql) = @_;

    # Test each new element and migrate as necessary
    my $ok = eval {
        return 0 unless defined $check;
        verbose("Running test SQL: $check\n");
        $star_db->do($check);
        return 1;
    };
    unless ($ok) {
        verbose("Test failed, performing update(s)\n");
        for (@$upgrade_sql) {
            verbose("Running update SQL: $_\n");
            $star_db->do($_);
        }
    }
}

sub usage {
    diag(<<END);
Usage: $0 [options]

Update the stars.db SQLite database for use with glyphinator.pl

Options:
  --verbose              - Be more verbose
  --quiet                - Only print errors
  --config <file>        - Specify a GLC config file, normally lacuna.yml.
  --db <file>            - Specify a star database, normally stars.db.
  --create-db            - Create the star database and initialize the schema.
  --upgrade              - Update database if any schema changes are required.
  --merge-db <file>      - Copy missing data from another database file
  --no-fetch             - Don't fetch probe data, only merge databases
  --no-vacuum            - Don't vacuum the db when finished
  --planet <name>        - Specify a planet to process.  This option can be
                           passed multiple times to indicate several planets.
                           If this is not specified, all relevant colonies will
                           be inspected.
END
    exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
