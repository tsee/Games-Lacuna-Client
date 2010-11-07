use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long qw(GetOptions);
use Text::CSV;
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

my $InputFile = 'stars.csv';
my $DbFile = 'map.sqlite';
GetOptions(
  's|starsfile=s' => \$InputFile,
  'd|dbfile=s' => \$DbFile,
);

LacunaMap::DB->import(
  $DbFile,
  cleanup => 'VACUUM',
);

my $csv = Text::CSV->new;
open my $fh, '<:encoding(utf8)', $InputFile
  or die "Can't open $InputFile for reading: $!";

# skip header
$csv->getline($fh);

my $lines = 0;
LacunaMap::DB->begin;
my @cols = qw(id name x y color zone);
while (my $row = $csv->getline($fh)) {
  $lines++;
  LacunaMap::DB->commit_begin
    if ($lines % 1000) == 0;
  LacunaMap::DB::Stars->create(
    map {($cols[$_], $row->[$_])} 0..4
  );
}
LacunaMap::DB->commit;

