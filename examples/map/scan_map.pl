use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use AnyEvent;
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

$| = 1;

use constant MINUTE => 60;

my $DbFile = 'map.sqlite';
GetOptions(
  'd|dbfile=s' => \$DbFile,
);

my $config_file = shift @ARGV || 'lacuna.yml';
die if not defined $config_file or not -e $config_file;

LacunaMap::DB->import(
  $DbFile,
  cleanup => 'VACUUM',
);

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

my $program_exit = AnyEvent->condvar;
my $int_watcher = AnyEvent->signal(
  signal => "INT",
  cb => sub {
    output("Interrupted!");
    undef $client;
    exit(1);
  }
);


# fetch min/max coords
my $emp_stat = $client->empire->get_status;
my $map_size = $emp_stat->{server}->{star_map_size};
my ($minx, $maxx) = @{$map_size->{x}};
my ($miny, $maxy) = @{$map_size->{y}};

help();
print "\n> ";
my $wait_for_input = AnyEvent->io(
  fh => \*STDIN, poll => "r",
  cb => sub {
    my $cmd = <STDIN>;
    if (not defined $cmd) {
      output("Good bye!");
      $program_exit->send;
      return;
    }
    $cmd =~ s/#.*$//;
    if ($cmd !~ /^\s*$/s) {
      chomp $cmd;
      if ($cmd =~ /^\s*exit\s*$/i) {
        output("Good bye!");
        $program_exit->send;
        return;
      }
      elsif ($cmd =~ /^\s*help\b/) {
        help();
      }
      elsif ($cmd =~ /^\s*scan\b/) {
        if ($cmd =~ /^\s*scan\s+(-?\d+)\s+(-?\d+)\s+(\d+)\s+(\d+)/) {
          my ($x, $y, $dx, $dy) = ($1, $2, $3, $4);
          output("Scanning area around ($x, $y) in range ($dx, $dy) for known bodies");
          scan($client, $x, $y, $dx, $dy);
        }
        elsif ($cmd =~ /^\s*scan\s+(-?\d+)\s+(-?\d+)/) {
          my ($x, $y) = ($1, $2);
          output("Scanning area around ($x, $y) for known bodies");
          scan($client, $x, $y);
        }
        else {
          output("Invalid scan command. Syntax: scan X Y [DX DY]");
        }
      }
      else {
        output("Invalid command input!");
      }
    } # end if got command

    print "\n" if not defined $cmd;
    print "> ";
  }
);


$program_exit->recv;


sub scan {
  my $client = shift;
  my $x = shift;
  my $y = shift;
  my $xspan = shift||20;
  my $yspan = shift||20;

  my $scan_minx = $x - int($xspan/2);
  my $scan_maxx = $x + int($xspan/2);
  my $scan_miny = $y - int($yspan/2);
  my $scan_maxy = $y + int($yspan/2);
  $scan_minx = $minx if $scan_minx < $minx;
  $scan_maxx = $maxx if $scan_maxx > $maxx;
  $scan_miny = $miny if $scan_miny < $miny;
  $scan_maxy = $maxy if $scan_maxy > $maxy;

  $xspan = $scan_maxx-$scan_minx;
  $yspan = $scan_maxy-$scan_miny;

  my $dx = 20;
  my $dy = 20;
  my $nx = $xspan/$dx;
  $nx = int($nx)+1 if $nx != int($nx);
  my $ny = $yspan/$dy;
  $ny = int($ny)+1 if $ny != int($ny);

  my $map = $client->map;
  foreach my $iy (0..$ny-1) {
    my $y1 = $scan_miny + $iy*$dy;
    my $y2 = $scan_miny + ($iy+1)*$dy;
    $y2 = $scan_maxy if $y2 > $scan_maxy;
    foreach my $ix (0..$nx-1) {
      my $x1 = $scan_minx + $ix*$dx;
      my $x2 = $scan_minx + ($ix+1)*$dx;
      $x2 = $scan_maxx if $x2 > $scan_maxx;

      _run_one_scan($map, $x1, $y1, $x2, $y2);
    }
  }


}

sub _run_one_scan {
  my ($map, $x1, $y1, $x2, $y2) = @_; # max 20x20!
  my $stars = $map->get_stars($x1, $y1, $x2, $y2);

  $stars = $stars->{stars};
  #warn Dumper $stars;
  LacunaMap::DB->begin;
  output("Found " . scalar(@$stars) . " stars");
  foreach my $star (@$stars) {

    if ($star->{bodies} and ref($star->{bodies}) eq 'ARRAY' and @{$star->{bodies}}) {
      my @unknown = LacunaMap::DB::Bodies->select('where star_id = ? and x is NULL', $star->{bodies}[0]{star_id});
      for (@unknown) {
        #output("Deleting existing unknown-positon body for this star: " . Dumper($_));
        $_->delete;
      }
      LacunaMap::DB->commit_begin if @unknown;

      foreach my $body (@{$star->{bodies}}) {
        my @existing = LacunaMap::DB::Bodies->select('where star_id = ? and (id is NULL or id = ?)', $body->{star_id}, $body->{id});
        for (@existing) {
          #output("Deleting existing body with same id: " . Dumper($_));
          $_->delete;
        }
        LacunaMap::DB->commit_begin if @existing;
        
        eval {
          my $dbbody = LacunaMap::DB::Bodies->create(
            ($body->{empire} ? (empire_id => $body->{empire}{id}) : ()),
            map {($_ => $body->{$_})} qw(
              id name x y star_id orbit type size water
            )
          );
        };
        if ($@) {
          warn $@;
          die Dumper $body;
        }
      } # end foreach bodies

      LacunaMap::DB->commit_begin;
    } # end if have bodies

  } # end foreach star
  LacunaMap::DB->commit;
}

sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}

sub help {
  print <<'HERE';
Interactive interface for scanning star maps. Commands:
- help
- exit
- scan X Y [DX DY]
  Scans a part of the map at position X/Y and stores the result in the DB.
  DX/DY is the size of the scanned area and defaults to 20x20. Do not scan
  the whole map this way as every 20x20 piece of the map will require one
  RPC API call!

HERE
}
