#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
foreach my $name ( sort keys %planets ) {

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the Archaeology Ministry
    my $arch_id = first {
            $buildings->{$_}->{name} eq 'Archaeology Ministry'
    } keys %$buildings;
    
    my $arch   = $client->building( id => $arch_id, type => 'Archaeology' );
    my $glyphs = $arch->get_glyphs->{glyphs};
    
    next if !@$glyphs;
    
    printf "%s\n", $name;
    print "=" x length $name;
    print "\n";
    
    @$glyphs = sort { $a->{type} cmp $b->{type} } @$glyphs;
    
    for my $glyph (@$glyphs) {
        printf "%s\n", ucfirst( $glyph->{type} );
    }
    
    print "\n";
}
