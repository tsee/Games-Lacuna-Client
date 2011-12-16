#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Number::Format        qw( format_number );
use List::Util            qw( max );
use Games::Lacuna::Client ();

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

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my $max_length = max map { length } keys %planets;

my @results;

# Scan each planet
foreach my $name ( sort keys %planets ) {

    # Load planet data
    my $planet = $client->body( id => $planets{$name} );
    my $body   = $planet->get_status->{body};

    next if $body->{type} eq 'space station';

    push @results, {
        name      => $name,
        happy     => format_number( $body->{happiness} ),
        happyhour => format_number( $body->{happiness_hour} ),
    };
}

my $max_name      = max map { length $_->{name} }      @results;
my $max_happy     = max map { length $_->{happy} }     @results;
my $max_happyhour = max map { length $_->{happyhour} } @results;

for my $planet (@results) {
    printf "%${max_name}s: %${max_happy}s @ %${max_happyhour}s/hr\n",
        $planet->{name},
        $planet->{happy},
        $planet->{happyhour};
}
