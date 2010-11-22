#!/usr/bin/perl
use strict;
use warnings;
use Games::Lacuna::Cache;
use Data::Dumper;

######################################
# Recommended usage: Run this script with an argument of 1, and check the 
# server calls. There should be one call for the Empire, and one per planet.
# Run it again in 10 minutes, and check for a lack of server calls. You can
# also check the extrapolation figures against your actual figures if you
# like.



my $refresh = $ARGV[0] || 0;
print "Refresh: $refresh \n";
binmode STDOUT, ":utf8";

my %opts = ('cfg_file' => "/path/to/lacuna.yml",
                         'cache_file' => "/path/to/lac_cache.dat",
                         'cache_debug' => 1,
                         'refresh' => $refresh);

                         

my $laluna = Games::Lacuna::Cache->new(%opts);

# Store your own data for more direct manipulation....
my $empire_data = $laluna->empire_data();
print "========= EMPIRE DATA ==========\n";
print Dumper($empire_data);
print "======= END EMPIRE DATA ========\n\n";

print "========= PLANET DATA ==========\n";
foreach my $planet (keys %{$laluna->planet_data()}){

    my $planet_data = $laluna->planet_data($planet);
    my $name = $empire_data->{'planets'}{$planet};
    utf8::decode($name);
    print "Waste per hour on $name : $planet_data->{'waste_hour'}\n";
    print "Extrapolated waste on $name: $planet_data->{'waste_stored'}\n";
}

print "======= END PLANET DATA ========\n\n";


# This will usually get back only basic data. You can request a building by ID
# to get full data. ->list_buildings_on_planet also creates client objects!
my @filters = ("spaceport");
print "========= BUILDING DATA ==========\n";
foreach my $planet (keys %{$laluna->planet_data()}){
    my $planet_data = $laluna->planet_data($planet);
    my @spaceports = $laluna->list_buildings_on_planet($planet, \@filters);
    foreach my $sp (@spaceports){
        print "Spaceport: $sp \n";
    }

}
print "======= END BUILDING DATA ========\n\n";




# Or use convenience methods, which means Cache will look after refreshing,
# but it's not as versatile. Since list_planets is the only thing that works.

my $planets = $laluna->list_planets();

print "========= PLANETS ==========\n";
foreach my $planet (keys %$planets){
    #XXX Note this. I don't do any encoding in the cache, it's up to you.
    my $name = $planets->{$planet};
    utf8::decode($name);
    print "$planet : $name \n";
}
print "======= END PLANETS ========\n\n";


#my @spaceports = $laluna->list_buildings(\@filters);

