#!/usr/bin/perl
#
# Script to find and report on all mining platform data
# Will spit out a csv list of them for further data extractions
#
# Usage: perl mining_platform.pl myaccount.yml
#  
# Right now only reports on ships that are either mining or can be set to mining
# so might change that since I'd prefer to list the ships that could be set later
# but might be delivering cargo at the time.

use strict;
use warnings;
use Games::Lacuna::Client;
use YAML::Any ();
use YAML::Dumper;
use Getopt::Long qw(GetOptions);

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

  my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
    # debug    => 1,
  );

my $platfile = "platform.yml";
my $shipfile = "mineship.yml";
GetOptions{
 'p=s' => \$platfile,
 's=s' => \$shipfile,
};

  my $dumper = YAML::Dumper->new;
  $dumper->indent_width(4);
  open(PLATO, ">", "$platfile") || die "Could not open $platfile";
  open(SHIPO, ">", "$shipfile") || die "Could not open $shipfile";

  my $empire = $client->empire;
  my $estatus = $empire->get_status->{empire};
  my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
                        keys %{$estatus->{planets}};

  my @ships;
  my @platforms;
  my @ship_ids;
  foreach my $planet (values %planets_by_name) {
    my %buildings = %{ $planet->get_buildings->{buildings} };

    my @b = grep {$buildings{$_}{name} eq 'Mining Ministry'}
                  keys %buildings;

    my @mining_stuff;
    push @mining_stuff, map  { $client->building(type => 'MiningMinistry', id => $_) } @b;

    for my $bld (@mining_stuff) {
      my $ships = $bld->view_ships();
      foreach my $ship ( @{$ships->{ships}} ) {
        next if grep {$ship->{id} eq $_ } @ship_ids;
        push @ship_ids, $ship->{id};
        $ship->{planet} = $ships->{status}->{body}->{name};
      }
      my $mini = $bld->view_platforms();
      foreach my $min ( @{$mini->{platforms}} ) {
        $min->{planet} = $mini->{status}->{body}->{name};
        $min->{max_platforms} = $mini->{max_platforms};
        $min->{hx} = $mini->{status}->{body}->{x};
        $min->{hy} = $mini->{status}->{body}->{y};
      }
      push @ships, @{$ships->{ships}};
      push @platforms, @{$mini->{platforms}};
    }
  }
  print SHIPO $dumper->dump(\@ships);
  print PLATO $dumper->dump(\@platforms);

exit;

# Old csv attempt, rather download data once and work on it remote
  printf "%s,%s,%s,%s,%s,%s\n", "Planet", "Task",
                   "Hold", "Speed", "Name","ID";
  foreach my $ship (sort byshipsort @ships) {
    printf "%s,%s,%d,%d,%s,%d\n",
           $ship->{planet}, $ship->{task},
           $ship->{hold_size}, $ship->{speed},
           $ship->{name}, $ship->{id};
  }
  close(SHIPO);
  printf "%s,%s,%s,%s\n", "Planet", "MaxP", "Cap", "ID";
  foreach my $plat (sort byplatsort @platforms) {
    printf "%s,%d,%d,%d\n",
      $plat->{planet},
      $plat->{max_platforms},
      $plat->{shipping_capacity},
      $plat->{id};
  }
exit;

sub byplatsort {
    $a->{planet} cmp $b->{planet} ||
    $a->{asteroid}->{star_name} cmp $b->{asteroid}->{star_name} ||
    $a->{asteroid}->{orbit} cmp $b->{asteroid}->{orbit};
}

sub byshipsort {
   $a->{planet} cmp $b->{planet} ||
    $a->{task} cmp $b->{task} ||
    $a->{name} cmp $b->{name} ||
    $b->{hold_size} <=> $a->{hold_size} ||
    $b->{speed} <=> $a->{speed};
}

