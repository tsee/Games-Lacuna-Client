#!/usr/bin/env perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use List::Util   qw( first );
use Date::Parse;
use Date::Format;
use utf8;

  my %opts = (
    h          => 0,
    v          => 0,
    config     => "lacuna.yml",
    logfile   => "log/arch_output.js",
#    priority  => "monazite,rutile,beryl,gold,chromite,fluorite,bauxite,trona,zircon,chalcopyrite,methane,kerogen,goethite,anthracite,halite,galena,gypsum,uraninite,sulfur,magnetite",
# "chromite,goethite,anthracite,rutile,bauxite,kerogen,fluorite,trona,beryl,methane,gypsum,magnetite,monazite,chalcopyrite,uraninite,sulfur,zircon,galena,gold,halite",

    priority  => "monazite,gold,anthracite,uraninite,trona,fluorite,kerogen,methane",
  );

  my $ok = GetOptions(\%opts,
    'planet=s@',
    'help|h',
    'datafile=s',
    'config=s',
    'excavators',
    'abandon=i',
    'dig=s',
    'priority=s',
    'view',
  );

  my @ore_types = qw(monazite rutile beryl gold
                     chromite fluorite bauxite trona
                     zircon chalcopyrite methane kerogen
                     goethite anthracite halite galena
                     gypsum uraninite sulfur magnetite);

  unless ( $opts{config} and -e $opts{config} ) {
    $opts{config} = eval{
      require File::HomeDir;
      require File::Spec;
      my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
      File::Spec->catfile(
        $dist,
        'login.yml'
      ) if $dist;
    };
    unless ( $opts{config} and -e $opts{config} ) {
      die "Did not provide a config file";
    }
  }
  usage() if ($opts{help} or !$ok);
  my $json = JSON->new->utf8(1);

  my $params = {};
  my $ofh;
  open($ofh, ">", $opts{logfile}) || die "Could not create $opts{logfile}";

  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config},
    rpc_sleep => 1,
    # debug    => 1,
  );

  my $data  = $glc->empire->view_species_stats();
  my $ename = $data->{status}->{empire}->{name};
  my $ststr = $data->{status}->{server}->{time};

# reverse hash, to key by name instead of id
  my %planets = map { $data->{status}->{empire}->{colonies}{$_}, $_ }
                  keys %{ $data->{status}->{empire}->{colonies} };

  my @priority_ore;
  if ($opts{dig}) {
    if ($opts{dig} eq "priority") {
      @priority_ore = grep { dumb_match($_, \@ore_types) } split(",", $opts{priority});
    }
    elsif ($opts{dig} eq "arch") {
      die "Upcoming enhancement to look at each arch along the way";
    }
    elsif ($opts{dig} eq "stats") {
      die "Upcoming enhancement to look at stats to prioritize";
    }
    elsif (grep { $opts{dig} eq $_ } keys %planets) {
      die "Upcoming enhancement to figure out via one archmin of empire";
    }
    else {
      print "Wrong argument for dig: $opts{dig}\n";
      usage();
    }
  }
  my $arch_hash = {};
  foreach my $pname ( sort keys %planets ) {
    next if ($opts{planet} and not (grep { lc $pname eq lc $_ } @{$opts{planet}}));
    print "Working on $pname\n";
# Load planet data
    my $body   = $glc->body( id => $planets{$pname} );
    my $result = $body->get_buildings;
    my $buildings = $result->{buildings};

    my $arch_id = first {
      $buildings->{$_}->{url} eq '/archaeology'
    } keys %$buildings;

    unless ($arch_id) {
      warn "No Archaeology on planet $pname\n";
      next;
    }

    my $arch =  $glc->building( id => $arch_id, type => 'Archaeology' );

    unless ($arch) {
      warn "No Archaeology!\n";
      next;
    }

    my $arch_out;
    if ($opts{view}) {
      $arch_out = $arch->view();
    }
    elsif ($opts{excavators}) {
      $arch_out = $arch->view_excavators();
    }
    elsif ($opts{subsidize}) {
#    $arch_out = $arch->subsidize();
    }
    elsif ($opts{abandon}) {
      $arch_out = $arch->abandon_excavator($opts{abandon});
      last;
    }
    elsif ($opts{dig}) {
      my $ores_avail = $arch->get_ores_available_for_processing();
      ORE: for my $pore (@priority_ore) {
        my $quan = $ores_avail->{ore}->{$pore} ? $ores_avail->{ore}->{$pore} : 0;
        if ($quan > 10_000) {
          my $ok = eval {
            $arch_out = $arch->search_for_glyph($pore);
          };
          if ($ok) {
            print "Searching for $pore on $pname.\n";
          }
          else {
            print "Error while searching for $pore on $pname.\n";
          }
          last ORE;
        }
      }
    }
    else {
      die "Nothing to do!\n";
    }
    $arch_hash->{$pname} = $arch_out;
  }

  print $ofh $json->pretty->canonical->encode($arch_hash);
  close($ofh);

  if ($opts{excavators}) {
    parse_arch($arch_hash);
  }
  else {
#    print $json->pretty->canonical->encode($arch_hash);
  }

  print "$glc->{total_calls} api calls made.\n";
  print "You have made $glc->{rpc_count} calls today\n";
exit; 

sub parse_arch {
  my $json = shift;

  for my $pname (sort keys %$json) {
    my $excavs = $json->{"$pname"}->{excavators};
    my $max_excavators = $json->{"$pname"}->{max_excavators};
    my $travel = $json->{"$pname"}->{travelling};
    printf "%20s: Has %2d of %2d sites and %2d en route\n", $pname, (scalar @$excavs -1), $max_excavators, $travel;
    @$excavs = sort { $a->{id} <=> $b->{id} } @$excavs;
    my $excav = shift(@$excavs);
    @$excavs = sort {$a->{body}->{name} cmp $b->{body}->{name} } @$excavs;
    unshift (@$excavs, $excav);

    for $excav ( @$excavs ) {
      my $type = $excav->{body}->{image};
      $type =~ s/-[1-8]$//;
      printf "%20s: %-3s %7s A: %2d, G: %2d, P: %2d, R: %2d, id: %5d\n",
        $excav->{body}->{name},
        $type,
        $excav->{distance},
        $excav->{artifact},
        $excav->{glyph},
        $excav->{plan},
        $excav->{resource},
        $excav->{id};
    }
  }
}

sub dumb_match {
  my ($str, $ref) = @_;

  for my $part (@{$ref}) {
    return 1 if ($str eq $part);
  }
  return 0;
}

sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --planet         PLANET_NAME
       --CONFIG_FILE    defaults to lacuna.yml
       --logfile        Output file, default log/arch_output.js
       --config         Lacuna Config, default lacuna.yml
       --excav          View excavator sites for named planet
       --subsidize      Pay 2e to finish current work
       --view           View options
       --dig  ARG       Do an ore search.
              ARG can be 1) "priority"  : Use priority option to set dig priority
                         2) "arch"      : Use current planet glyph inventory to set priority
                         3) PLANET      : Use PLANET's glyph inventory to see what glyph is least in
                                          inventory and set a priority string based on it.
                         4) "stats"     : Make a priority list based on overall stats. Will do least to most popular.
                         Note: priority is the least RPC use method, though PLANET and stats is only one extra call.
                               arch has to poll each planet's archeology before searching.
       --priority STRING  A list of ores seperated by a comma.  Example "sulfur,rutile,anthracite"
                          If 10,000 units of first ore isn't available, go to next.  If none in the list qualify, skip.
                          Default Order is: (Based off a glyph list in May 2015)
                            "monazite,rutile,beryl,gold,chromite,fluorite,bauxite,trona,zircon,chalcopyrite,
                             methane,kerogen,goethite,anthracite,halite,galena,gypsum,uraninite,sulfur,magnetite"
END_USAGE

}
