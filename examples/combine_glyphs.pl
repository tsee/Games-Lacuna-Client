#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my $planet_name;
my @glyphs;

GetOptions(
    'planet=s' => \$planet_name,
    'glyph=s@' => \@glyphs,
);

usage() if !$planet_name;

usage( "Must combine at least 1 glyph" )
    if !@glyphs;

usage ( "Cannot combine more than 4 glyphs" )
    if @glyphs > 4;

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


# Load planet data
my $planet    = $client->body( id => $planets{$planet_name} );
my $buildings = $planet->get_buildings->{buildings};

# Find the Archaeology Ministry
my $arch_id = first {
        $buildings->{$_}->{name} eq 'Archaeology Ministry'
} keys %$buildings;

die "Planet does not have an Archaeology Ministry\n"
    if !$arch_id;

my $arch_min         = $client->building( id => $arch_id, type => 'Archaeology' );
my $candidate_glyphs = $arch_min->get_glyphs->{glyphs};
my @use_glyphs;

WANT:
for my $want_glyph ( @glyphs ) {
    for my $candidate ( @$candidate_glyphs ) {
        next if grep { $candidate->{id} == $_->{id} }
            @use_glyphs;

        next if $candidate->{type} ne lc $want_glyph;

        push @use_glyphs, $candidate;
        next WANT;
    }

    die "Do not have glyph '$want_glyph' available\n";
}

my $return = $arch_min->assemble_glyphs(
    [ map { $_->{id} } @use_glyphs ]
);

printf "Successfully created a '%s'\n", $return->{item_name};
exit;


sub usage {
    my ($message) = @_;

    $message = $message ? "$message\n\n" : '';

    die <<"END_USAGE";
${message}Usage: $0 CONFIG_FILE
    --planet PLANET_NAME
    --glyph  GLYPH_NAME
    --glyph  GLYPH_NAME

CONFIG_FILE defaults to 'lacuna.yml' in the current directory.

--planet is required.

2 to 4 --glyph arguments are required, in the correct recipe order.

END_USAGE

}
