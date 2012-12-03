#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();
use Games::Lacuna::Client::Types
  qw( get_tags building_type_from_label meta_type );
use JSON;
use utf8;

my @planets;
my @skip_planets;
my $cfg_file = "lacuna.yml";
my $skip     = 1;
my $dump     = 0;
my $outfile  = 'log/data_plans.js';

GetOptions(
    'planet=s@' => \@planets,
    'config=s'  => \$cfg_file,
    'skip=s@'   => \@skip_planets,
    'outfile=s' => \$outfile,
    'dump'      => \$dump,
);

unless ( $cfg_file and -e $cfg_file ) {
    $cfg_file = eval {
        require File::HomeDir;
        require File::Spec;
        my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
        File::Spec->catfile( $dist, 'login.yml' ) if $dist;
    };
    unless ( $cfg_file and -e $cfg_file ) {
        die "Did not provide a config file";
    }
}

my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,

    # debug    => 1,
);

my $pf;
if ($dump) {
    open( $pf, ">", "$outfile" ) or die "Could not open $outfile for writing\n";
}

my $json = JSON->new->utf8(1);

# Load the planets
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
my $max_length;
my $all_plans;
my %plan_hash;
foreach my $pname ( sort keys %planets ) {
    next if ( scalar @planets and !( grep { lc $pname eq lc $_ } @planets ) );
    next
      if ( scalar @skip_planets and ( grep { lc $pname eq lc $_ } @planets ) );
    sleep 2;

    # Load planet data
    my $planet = $client->body( id => $planets{$pname} );
    my $result = $planet->get_buildings;
    my $body   = $result->{status}->{body};

    my $buildings = $result->{buildings};

    next if $result->{status}{body}{type} eq 'space station';

    # PPC or SC
    my $command_url =
      $result->{status}{body}{type} eq 'space station'
      ? '/stationcommand'
      : '/planetarycommand';

    # Find the Command
    my $command_id = first {
        $buildings->{$_}{url} eq $command_url;
    }
    grep {
        $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100
      }
      keys %$buildings;

    next unless $command_id;

    my $command_type =
      Games::Lacuna::Client::Buildings::type_from_url($command_url);
    my $command = $client->building( id => $command_id, type => $command_type );
    my $plans = $command->view_plans->{plans};

    next if !@$plans;

    $plan_hash{"$pname"} = $plans;

    printf "%s\n", $pname;
    print "=" x length $pname;
    print "\n";

    $max_length = max map { length $_->{name} } @$plans;

    my $total_plans = 0;
    for my $plan ( sort srtname @$plans ) {
        my $ebl = "  ";
        my $pls = " ";
        if ( $plan->{extra_build_level} ) {
            $ebl = $plan->{extra_build_level};
            $pls = "+";
        }
        printf "%${max_length}s, level %2s %s %2s (%5d)\n",
          $plan->{name},
          $plan->{level},
          $pls, $ebl,
          $plan->{quantity};

        $total_plans += $plan->{quantity};
    }
    print "\n";
    print "Total Plans: ", $total_plans, "\n\n";
    $all_plans += $total_plans;
    sleep 2;
}
print "We have $all_plans plans.\n";
if ($dump) {
    print $pf $json->pretty->canonical->encode( \%plan_hash );
    close $pf;
}
exit;

sub srtname {
    my $abit = $a->{name};
    my $bbit = $b->{name};
    $abit =~ s/ //g;
    $bbit =~ s/ //g;
    my $aebl = ( $a->{extra_build_level} ) ? $a->{extra_build_level} : 0;
    my $bebl = ( $b->{extra_build_level} ) ? $b->{extra_build_level} : 0;
    $abit cmp $bbit
      || $a->{level} <=> $b->{level}
      || $aebl <=> $bebl;
}
