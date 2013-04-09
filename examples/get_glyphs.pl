#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util qw(min max);
use List::MoreUtils qw( uniq );
use Getopt::Long qw(GetOptions);
use Games::Lacuna::Client ();
use JSON;

my %opts;
$opts{data}   = "log/glyph_data.js";
$opts{config} = 'lacuna.yml';

GetOptions( \%opts, 'planet=s@', 'data=s', 'config=s', );

open( DUMP, ">", "$opts{data}" ) or die "Could not write to $opts{data}\n";

unless ( $opts{config} and -e $opts{config} ) {
    $opts{config} = eval {
        require File::HomeDir;
        require File::Spec;
        my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
        File::Spec->catfile( $dist, 'login.yml' ) if $dist;
    };
    unless ( $opts{config} and -e $opts{config} ) {
        die "Did not provide a config file";
    }
}

my $glc = Games::Lacuna::Client->new(
    cfg_file  => $opts{config},
    rpc_sleep => 2,

    # debug    => 1,
);

# Load the planets
my $empire = $glc->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
my $glyph_hash = {};
foreach my $pname ( sort keys %planets ) {
    next
      if ( $opts{planet}
        and not( grep { lc $pname eq lc $_ } @{ $opts{planet} } ) );
    print "Checking $pname - ";

    # Load planet data
    my $planet    = $glc->body( id => $planets{$pname} );
    my $result    = $planet->get_buildings;
    my $buildings = $result->{buildings};

    if ( $result->{status}{body}{type} eq 'space station' ) {
        print "Space Station\n";
        next;
    }

    # Find the Archaeology Ministry or Trade Ministry
    my $bld_id = List::Util::first {
        $buildings->{$_}->{name}      eq 'Archaeology Ministry'
          or $buildings->{$_}->{name} eq 'Trade Ministry'
          or $buildings->{$_}->{name} eq 'Subspace Transporter';
    }
    grep {
        $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100
      }
      keys %$buildings;

    unless ($bld_id) {
        print
          "No Archaeology Ministry, Trade Ministry, or Subspace Transporter.\n";
    }

    print $buildings->{$bld_id}->{name}, " found.\n";
    my $bld_pnt;
    if ( $buildings->{$bld_id}->{name} eq "Archaeology Ministry" ) {
        $bld_pnt = $glc->building( id => $bld_id, type => 'Archaeology' );
    }
    elsif ( $buildings->{$bld_id}->{name} eq "Trade Ministry" ) {
        $bld_pnt = $glc->building( id => $bld_id, type => 'Trade' );
    }
    elsif ( $buildings->{$bld_id}->{name} eq "Subspace Transporter" ) {
        $bld_pnt = $glc->building( id => $bld_id, type => 'Transporter' );
    }
    else {
        print $buildings->{$bld_id}->{name}, " is invalid!\n";
        next;
    }

    my $glyphs = $bld_pnt->get_glyph_summary()->{glyphs};

    $glyph_hash->{$pname}->{glyphs} = $glyphs;

    #    my $sport_status =  $am->view;
    #    delete $sport_status->{building};
    #    delete $sport_status->{status};
    #    $glyph_hash->{$pname}->{view} = $sport_status;
}

my $json = JSON->new->utf8(1);
$json = $json->pretty(    [1] );
$json = $json->canonical( [1] );

print DUMP $json->pretty->canonical->encode($glyph_hash);
close(DUMP);
exit;
