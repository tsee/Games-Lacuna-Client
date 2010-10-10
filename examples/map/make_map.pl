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

my $my_empire_id = 299;

my $min_x = LacunaMap::DB::Stars->min_x-10;
my $max_x = LacunaMap::DB::Stars->max_x+10;
my $min_y = LacunaMap::DB::Stars->min_y-10;
my $max_y = LacunaMap::DB::Stars->max_y+10;

my ($xsize, $ysize) = ($max_x - $min_x + 1, $max_y - $min_y + 1);
my $img = Imager->new(xsize => $xsize, ysize => $ysize);
my $black = Imager::Color->new(0, 0, 0);
my $red   = Imager::Color->new(255, 0, 0);
my $green = Imager::Color->new(0, 255, 0);
my $blue  = Imager::Color->new(0, 0, 255);
my $white = Imager::Color->new(255, 255, 255);
my $grey  = Imager::Color->new(180, 180, 180);
$img->box(filled => 1, color => $black);

LacunaMap::DB::Stars->iterate(sub {
  $img->setpixel(x => $_->x - $min_x, y => $_->y - $min_y, color => $grey);
});

LacunaMap::DB::Bodies->iterate(sub {
  my $body = $_;
  my $color;
  if ($body->empire_id && $body->empire_id == $my_empire_id) { $color = $green; }
  elsif ($body->empire_id) { $color = $red; }
  elsif ($body->type =~ /habitable/i) { $color = $blue; }
  else { $color = $white; }
  $img->setpixel(x => $body->x - $min_x, y => $body->y - $min_y, color => $color);
});


$img->write(file => "map.png");

