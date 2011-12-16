#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Cache;
use Data::Dumper;

binmode STDOUT, ":utf8";

my $refresh = $ARGV[0];
my $shiptype = $ARGV[1];
my $coords = $ARGV[2];


usage() unless $shiptype && $coords;

my %opts = ('cfg_file' => "/path/to/lacuna.yml",
            'cache_file' => "/path/to/lac_cache.dat",
            'refresh' => $refresh);

unless ( $opts{cfg_file} and -e $opts{cfg_file} ) {
  $opts{cfg_file} = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $opts{cfg_file} and -e $opts{cfg_file} ) {
    die "Did not provide a config file";
  }
}

my ($t_type, $t_name) = split(":", $coords);
my $target_id = { $t_type => $t_name };

my $laluna = Games::Lacuna::Cache->new(%opts);
my $empire_data = $laluna->empire_data();
my $total_ships = 0;
my $problem_ships = 0;

foreach my $planet (keys %{$empire_data->{'planets'}}){
    my $status = $laluna->planet_data($planet);
    my $ship_count = 0;
    my $name = $status->{'name'};
    utf8::decode($name);

    print "\n+=========== $name ============\n";

    my @filters = ("spaceport");
    foreach my $sp ($laluna->list_buildings_on_planet($planet, \@filters)){
        my $re = $laluna->{'OBJECTS'}->{'buildings'}->{$sp};
        print "| Found Spaceport $re->{'building_id'} \n";
        my $rec = $re->get_ships_for($planet, $target_id);
        if (scalar(@{$rec->{'available'}}) > 0){
            foreach my $ship (@{$rec->{'available'}}){
          #      print Dumper($ship);
                if ($ship->{'type'} eq $shiptype){
                    print "| Sending $shiptype " .  $ship->{'id'} . " from $name\n";
                    my $response = $re->send_ship($ship->{'id'}, $target_id);
                    if ($response->{'ship'}->{'date_arrives'}){
                        print "| Success - scheduled arrival: ".  $response->{'ship'}->{'date_arrives'} .  "\n";
                        $total_ships++;
                    }else{
                        print "| PROBLEM WITH LAUNCH!! Could not send " .
                            $ship->{'id'} . "\n";
                            $problem_ships++;
                    }
                }
            }
        }
    }

    print "|\n+========= End $name ==========\n\n";

}


if ($total_ships > 0 ){
    print "Sent $total_ships $shiptype to $t_name ! Your empire has much to be proud of! \n";
}else{
    print "No ships found in your Empire capable of such a mission.\nTruly this is a sad day.\n\n";
}

sub usage{
    print "Usage: launchpad.pl refresh shiptype target. Consult documentation for target format\n";
    exit;
}

=head1 SYNOPSIS

Usage: launchpad.pl refresh shiptype "target"

Sends all available ships of type shiptype to target.

You must supply shiptype and target. Target should be of the form:

        "body_id:id_goes_here"
        "body_name:My Planet"
        "star_id:id_goes_here"
        "star_name:My Star"

Examples:
        "body_id:1"
        "body_name:Ud Vaijeu Eedd 4"
        "star_id:5"
        "star_name:Knioschow"

Support for x/y not yet implemented.


=head1 AUTHOR

Jai Cornes, E<lt>solitaire@tygger.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jai Cornes

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.



