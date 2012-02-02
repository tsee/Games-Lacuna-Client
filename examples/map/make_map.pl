use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Imager;
use Getopt::Long qw(GetOptions);
use YAML::Any ();
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

our $cfg_file = 'map.yml';
our $DbFile = 'map.sqlite';
our @HighlightStars;
our $private = 0; # If private, our colonies are green and alliance is purple
GetOptions(
  'c|cfg_file=s' => \$cfg_file,
  'd|dbfile=s' => \$DbFile,
  'hl|highlight-star=s@' => \@HighlightStars,
  'p|private=i' => \$private,
);

my %highlight_star_names;
my %highlight_star_ids;
my $get_extra_star_info = '';
if (@HighlightStars) {
  $get_extra_star_info = ', stars.id, stars.name '; # hack!
}
foreach my $hl (@HighlightStars) {
  if ($hl =~ /^\d+$/) {
    $highlight_star_ids{$hl} = 1;
  }
  else {
    $highlight_star_names{$hl} = 1;
  }
}

my $config;
if (-e $cfg_file) {
    $config=YAML::Any::LoadFile($cfg_file);
}

my $my_empire_id = $config->{empire_id} || '';
unless ( $my_empire_id )
{
    die "empire_id missing from $cfg_file\n";
}

my @allied_empires = @{ $config->{allied_empires} };
unless ( @allied_empires )
{
    warn "No allied_empires found.\n";
}
my %allied_empires = map {($_ => 1)} @allied_empires;

LacunaMap::DB->import($DbFile);

# Let's hardcode these for the sake of a nicer map
#my $min_x = LacunaMap::DB::Stars->min_x-10;
#my $max_x = LacunaMap::DB::Stars->max_x+10;
#my $min_y = LacunaMap::DB::Stars->min_y-10;
#my $max_y = LacunaMap::DB::Stars->max_y+10;
my $min_x = -1500;
my $max_x = 1500;
my $min_y = -1500;
my $max_y = 1500;

my $xborder = 21;
my $yborder = 21;
my ($map_xsize, $map_ysize) = ($max_x - $min_x + 1, $max_y - $min_y + 1);
my ($xsize, $ysize) = ($map_xsize+$xborder, $map_ysize+$yborder);

my $img = Imager->new(xsize => $xsize+$xborder, ysize => $ysize);
my $black  = Imager::Color->new(0, 0, 0);
my $red    = Imager::Color->new(255, 0, 0);
my $yellow = Imager::Color->new(255, 255, 0);
my $green  = Imager::Color->new(0, 255, 0);
my $blue   = Imager::Color->new(0, 0, 255);
my $white  = Imager::Color->new(255, 255, 255);
my $grey   = Imager::Color->new(80, 80, 80);
my $purple = Imager::Color->new(255, 0, 255);
$img->box(filled => 1, color => $black);

$img->line(x1 => $map_xsize+1, x2 => $map_xsize+1, y1 => 1, y2 => $map_ysize+1, color => $white);
$img->line(x1 => 1, x2 => $map_xsize+1, y1 => $map_ysize+1, y2 => $map_ysize+1, color => $white);

use Imager::Fill;
my $fill1 = Imager::Fill->new(solid=>$green);
$img->box(xmin => $map_xsize+9, xmax => $map_xsize+13,
          ymin => int($map_ysize/4.), ymax => int($map_ysize*3/4),
          color => $green, fill => $fill1);
$img->polygon(
  color => $green, fill => $fill1,
  points => [
    [$map_xsize+11, int($map_ysize*1/4.)-4],
    [$map_xsize+11-9, int($map_ysize*1/4.)+15],
    [$map_xsize+11+9, int($map_ysize*1/4.)+15],
  ],
);

$img->box(xmin => int($map_xsize/4.), xmax => int($map_xsize*3/4),
          ymin => $map_ysize+10, ymax => $map_ysize+12,
          color => $green, fill => $fill1);
$img->polygon(
  color => $green, fill => $fill1,
  points => [
    [int($map_xsize*3/4.)+4, $map_ysize+11],
    [int($map_xsize*3/4.)-15, $map_ysize+11-9],
    [int($map_xsize*3/4.)-15, $map_ysize+11+9],
  ],
);

# stars with known-position bodies or no bodies
LacunaMap::DB->iterate(<<"QUERY",
  select stars.x, stars.y$get_extra_star_info
    from stars
    left outer join bodies on stars.id = bodies.star_id
    where (bodies.x is not NULL)          -- known-position body
          or
          (bodies.sql_primary_id is NULL) -- no bodies
QUERY
  sub {
    my ($x, $y, $id, $name) = @$_;
    my $color = $grey;
    if (defined $name and
        (exists $highlight_star_names{$name} or
         exists $highlight_star_ids{$id}))
    {
      $color = $green;
    }
    $img->setpixel(x => $x - $min_x, y => $map_ysize-($y - $min_y), color => $color);
  }
);

# stars with unknown-position bodies
LacunaMap::DB->iterate(<<"QUERY",
  select stars.x, stars.y$get_extra_star_info
    from stars inner join bodies on stars.id = bodies.star_id
    where bodies.x is NULL
QUERY
  sub {
    my ($x, $y, $id, $name) = @$_;
    my $color = $yellow;
    if (defined $name and
        (exists $highlight_star_names{$name} or
         exists $highlight_star_ids{$id}))
    {
      $color = $green;
    }
    $img->setpixel(x => $x - $min_x, y => $map_ysize-($y - $min_y), color => $color);
  }
);

LacunaMap::DB::Bodies->iterate(
  'where bodies.x is not NULL',
  sub {
    my $body = $_;
    if (not defined $body->x or not defined $body->y) {
      return;
    }
    my $color;
    my $eid = $body->empire_id;
    if ($eid) {
      if ($eid == $my_empire_id) { $color = $green; }
      elsif ($allied_empires{$eid}) {
        if ($private) { $color = $purple; }
        else { $color = $green; }
      }
      else { $color = $red; }
    }
    elsif ($body->type =~ /habitable/i) { $color = $blue; }
    else { $color = $white; }
    $img->setpixel(x => $body->x - $min_x, y => $map_ysize-($body->y - $min_y), color => $color);
  }
);

$img->write(file => "map.png")
    or die q{Cannot save map.png, }, $img->errstr;


