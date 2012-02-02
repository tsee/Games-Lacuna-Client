#!/usr/bin/perl
#
# This program populates the database of glyphinator
# with derived star data.
# Original program from AHart based on work by cxreg.
#
use strict;
use warnings;

use DBI;
use FindBin;
use Getopt::Long;
use POSIX qw(strftime);

use lib "$FindBin::Bin/../lib";
use Text::CSV_XS;

my %opts;
GetOptions( \%opts,
           'h|help',
           'db=s',
           'csv=s'
);

usage() if $opts{h};

my $star_db = DBI->connect("dbi:SQLite:$opts{db}")
    or die "Can't open star database $opts{db}: $DBI::errstr\n";
$star_db->{RaiseError} = 1;
$star_db->{PrintError} = 0;
$star_db->{AutoCommit} = 0;

my $clear_stars_table
    = $star_db->prepare_cached(
    'delete from stars'
    );
my $clear_orbitals_table
    = $star_db->prepare_cached(
    'delete from orbitals'
    );

my $insert_star
    = $star_db->prepare_cached(
    'insert into stars (id, name, x, y, color, zone, last_checked) values (?,?,?,?,?,?,?)'
    );

my $insert_orbital = $star_db->prepare_cached(
    'insert into orbitals (star_id, orbit, x, y) values (?,?,?,?)' );

my $when = strftime "%Y-%m-%d %T", gmtime;

my $planets = [
    sub { ( 1, $_[0] + 1, $_[1] + 2 ) },    # Orbit 1: X+1, Y+2
    sub { ( 2, $_[0] + 2, $_[1] + 1 ) },    # Orbit 2: X+2, Y+1
    sub { ( 3, $_[0] + 2, $_[1] - 1 ) },    # Orbit 3: X+2, Y-1
    sub { ( 4, $_[0] + 1, $_[1] - 2 ) },    # Orbit 4: X+1, Y-2
    sub { ( 5, $_[0] - 1, $_[1] - 2 ) },    # Orbit 5: X-1, Y-2
    sub { ( 6, $_[0] - 2, $_[1] - 1 ) },    # Orbit 6: X-2, Y-1
    sub { ( 7, $_[0] - 2, $_[1] + 1 ) },    # Orbit 7: X-2, Y+1
    sub { ( 8, $_[0] - 1, $_[1] + 2 ) },    # Orbit 8: X-1, Y+2
];

my $csv = Text::CSV_XS->new( { binary => 1 } )
    or die "Cannot use CSV: " . Text::CSV_XS->error_diag();
open my $fh, "<:encoding(utf8)", $opts{csv} or die "$opts{csv}: $!";
$clear_stars_table->execute();
$clear_orbitals_table->execute();
while ( my $row = $csv->getline($fh) ) {

    my ( $id, $name, $x, $y, $color, $zone ) = @$row;
    warn "Inserting star $name at $x, $y\n";
    $insert_star->execute( $id, $name, $x, $y, $color, $zone, $when )
        or die "Can't insert star: " . $insert_star->errstr;

    for my $extrapolate (@$planets) {
        my ( $orbit, $x, $y ) = $extrapolate->( $x, $y );
        $insert_orbital->execute( $id, $orbit, $x, $y );
    }
}
$csv->eof or $csv->error_diag();
close $fh;

$star_db->commit;

sub usage {
diag(<<END);
Usage: $0 [options]

This program will populate a stars.db with orbital data derived from stars.csv.
You will need to create the DB using cxreg's star_util_db.pl first.
stars.csv can be downloaded from http://SERVERNAME.lacunaexpanse.com.s3.amazonaws.com/stars.csv

Options:
  --db  DB_FILE    stars.db location
  --csv STAR_FILE  stars.csv location
END
exit 1;

}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

