use strict;
use warnings;
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use AnyEvent;
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

$| = 1;

use constant MINUTE => 60;

my $InputFile = 'stars.csv';
my $DbFile = 'map.sqlite';
GetOptions(
  's|starsfile=s' => \$InputFile,
  'd|dbfile=s' => \$DbFile,
);

my $config_file = shift @ARGV;
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

print "\n\n> ";
my $wait_for_input = AnyEvent->io(
  fh => \*STDIN, poll => "r",
  cb => sub {
    my $cmd = <STDIN>;
    if (defined $cmd and $cmd !~ /^\s*$/s) {
      chomp $cmd;
      if ($cmd =~ /^\s*exit\s*$/i) {
        output("Good bye!");
        $program_exit->send;
      }
      elsif ($cmd =~ /^\s*scan\b/) {
        if ($cmd =~ /^\s*scan\s+(-?\d+)\s+(-?\d+)/) {
          my ($x, $y) = ($1, $2);
          output("Scanning area around ($x, $y) for known bodies");
          scan($client, $x, $y);
        }
        else {
          output("Invalid scan command. Syntax: scan X Y");
        }
      }
      else {
        output("Invalid command input!");
      }
    } # end if got command

    print "> ";
  }
);


#my $empire = $client->empire;
#my $estatus = $empire->get_status->{empire};
#my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
#                      keys %{$estatus->{planets}};
# Beware. I think these might contain asteroids, too.
# TODO: The body status has a 'type' field that should be listed as 'habitable planet'

$program_exit->recv;


sub scan {
  my $client = shift;
  my $x = shift;
  my $y = shift;
  my $map = $client->map;

  my $dx = 20;
  my $dy = 20;

  my $x1 = $x-int($dx/2);
  my $x2 = $x+int($dx/2);
  my $y1 = $y-int($dy/2);
  my $y2 = $y+int($dy/2);

  my $stars = $map->get_stars($x1, $y1, $x2, $y2);

  $stars = $stars->{stars};
  #warn Dumper $stars;
  LacunaMap::DB->begin;
  output("Found " . scalar(@$stars) . " stars");
  foreach my $star (@$stars) {
    if ($star->{bodies} and ref($star->{bodies}) eq 'ARRAY') {
      foreach my $body (@{$star->{bodies}}) {
        my @existing = LacunaMap::DB::Bodies->select('where id = ?', $body->{id});
        $_->delete for @existing;
        my $dbbody = LacunaMap::DB::Bodies->create(
          ($body->{empire} ? (empire_id => $body->{empire}{id}) : ()),
          map {($_ => $body->{$_})} qw(
            id name x y star_id orbit type size water
          )
        );
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
