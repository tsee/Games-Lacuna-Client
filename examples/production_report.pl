#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Number::Format        qw( format_number );
use List::Util            qw( max );
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
);

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my @types = qw( food ore water energy waste );

# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if defined $planet_name && $planet_name ne $name;

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}{body};

    print "$name\n";
    print "=" x length $name;
    print "\n";

    my $max_hour     = max map { length format_number $body->{$_."_hour"} }     @types;
    my $max_stored   = max map { length format_number $body->{$_."_stored"} }   @types;
    my $max_capacity = max map { length format_number $body->{$_."_capacity"} } @types;

    for my $type (@types) {
        printf "%6s: %${max_hour}s/hr - %${max_stored}s / %${max_capacity}s\n",
            ucfirst($type),
            format_number( $body->{$type."_hour"} ),
            format_number( $body->{$type."_stored"} ),
            format_number( $body->{$type."_capacity"} );
    }

    print "\n";
}
