use strict;
use warnings;
use Text::CSV;
use Imager;

open my $fh, "<:encoding(utf8)", shift @ARGV or die $!;
my $csv = Text::CSV->new();

my $max_x = 1500;
my $max_y = 1500;

my $img = Imager->new(xsize => 2*$max_x, ysize => 2*$max_y);
my $black = Imager::Color->new(0, 0, 0);
my $red   = Imager::Color->new(255, 0, 0);
my $green = Imager::Color->new(0, 255, 0);
my $grey  = Imager::Color->new(180, 180, 180);
$img->box(filled => 1, color => $black);

$csv->getline( $fh );
while ( my $row = $csv->getline( $fh ) ) {
  my ($x, $y) = @{$row}[2, 3];
  $img->setpixel(x => $max_x+$x, y => $max_y+$y, color => $grey);
}
close $fh;

$img->write(file => "map.png");

