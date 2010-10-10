use strict;
use warnings;
use Imager;
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

my $DbFile = 'map.sqlite';
GetOptions(
  'd|dbfile=s' => \$DbFile,
);

LacunaMap::DB->import($DbFile);

my $min_x = LacunaMap::DB::Stars->min_x;
my $max_x = LacunaMap::DB::Stars->max_x;
my $min_y = LacunaMap::DB::Stars->min_y;
my $max_y = LacunaMap::DB::Stars->max_y;

my ($xsize, $ysize) = ($max_x - $min_x + 1, $max_y - $min_y + 1);
my $img = Imager->new(xsize => $xsize, ysize => $ysize);
my $black = Imager::Color->new(0, 0, 0);
my $red   = Imager::Color->new(255, 0, 0);
my $green = Imager::Color->new(0, 255, 0);
my $grey  = Imager::Color->new(180, 180, 180);
$img->box(filled => 1, color => $black);

LacunaMap::DB::Stars->iterate(sub {
  $img->setpixel(x => $_->x - $min_x, y => $_->y - $min_y, color => $grey);
});

$img->write(file => "map.png");

