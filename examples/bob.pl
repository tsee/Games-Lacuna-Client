#!/usr/bin/perl
use strict;
use warnings;
<<<<<<< HEAD
use Games::Lacuna::Cachedev;
use Data::Dumper;

my $refresh = $ARGV[0] || 0;
#print "Refresh: $refresh \n";
binmode STDOUT, ":utf8";

my %opts = ('cfg_file' => "/path/to/lacuna.yml",
            'cache_file' => "/path/to/.lac_cache.dat",
            'refresh' => $refresh);


my $laluna = Games::Lacuna::Cache->new(%opts);
=======
use Games::Lacuna::Cache;
use Data::Dumper;

my $refresh = $ARGV[0] || 0;
print "Refresh: $refresh \n";
binmode STDOUT, ":utf8";



my $laluna = Games::Lacuna::Cache->new($refresh);
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182
my $empire_data = $laluna->empire_data();

my %planet_hash;
my $display_count = 1;
foreach (keys %{$empire_data->{'planets'}}){
    my $name = $empire_data->{'planets'}->{$_};
    utf8::decode($name);

    print "$display_count) $name \n";
    $planet_hash{$display_count} = $_;
    $display_count++;
}

print "Enter a planet number: ";
my $num = <STDIN>;
chomp $num;

my $planet = $planet_hash{$num};
my @buildings = $laluna->list_buildings_on_planet($planet);
if (scalar(@buildings) == 0) { 
    print "No buildings for $planet??\n";
}
my %building_hash;
my $building_count = 1;
my $name = $empire_data->{'planets'}->{$planet};
utf8::decode($name); 
print "====Buildings on $name ====\n";
foreach my $id (@buildings) {
    my $info = $laluna->building_data($id);

    $building_hash{$building_count} = {$id => $info};

    print "$building_count) $info->{'name'} (L$info->{'level'} ";
    if ($info->{'pending_build'}){
        print "- $info->{'pending_build'}->{'seconds_remaining'} seconds remaining to L "; 
        print $info->{'level'} + 1 ;
    }
    print ")\n";

    $building_count++;
}

print "Enter a building number: ";
$num = <STDIN>;
chomp $num;

# We know it only has one key ....
foreach my $key (keys %{$building_hash{$num}}){
    my $info = $building_hash{$num}->{$key};
    print "Upgrading " . $info->{'name'} . "\n";
    my $cur_level = $info->{'level'}; 
    if ($info->{'pending_build'}){
        $cur_level = $info->{'level'} + 1;
    }
    print "Enter desired level (currently $cur_level) :";

    my $new_lev = <STDIN>;
    chomp($new_lev);
    my $attempts = 0;
    while ($cur_level < $new_lev){
        if ($attempts > $new_lev && $cur_level == 0){
            #Something went wrong, and we've tried more than the number of
            #levels we're building to. Bail.
            print "Something has gone terribly wrong. I've tried $attempts
                times to build to #new_lev, and I just can't!\n";
            exit;
        }else{
            if ($cur_level == 0){
                # Give it a minute, just in case. Easier than actually
                # checking the return value...
                sleep(180);
            }
<<<<<<< HEAD
            $cur_level = schedule_build($key, $new_lev, $planet);
=======
            $cur_level = schedule_build($key, $new_lev);
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182
            $attempts++;
        }
    }

}

sub schedule_build{
    use vars qw($laluna);
<<<<<<< HEAD
    my ($id, $lev, $planet) = @_;
    my %costs;
    my $sleep;
    #TODO Extend Cache to cache views as well. 
    my $building_info = $laluna->view_building($id);
    my $planet_data = $laluna->planet_data($planet);
=======
    my ($id, $lev) = @_;
    my %costs;
    my $sleep;
    #TODO Extend Cache to cache views as well. 
    my $response = $laluna->{'OBJECTS'}->{'buildings'}->{$id}->view();
    my $status = $response->{'status'};
    my $building_info = $response->{'building'};
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182


    if ($building_info->{'pending_build'}){
        $sleep = $building_info->{'pending_build'}->{'seconds_remaining'};
        print "Build pending - sleeping $sleep...\n";
        sleep $sleep;
        # Check every time, just in case.
<<<<<<< HEAD
        $building_info = $laluna->view_building($id);
=======
        $response = $laluna->{'OBJECTS'}->{'buildings'}->{$id}->view();
        $status = $response->{'status'};
        $building_info = $response->{'building'};
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182
    }
    $sleep = 0;

    #print Dumper($building_info);
    foreach my $res (qw(water ore energy)){
        print "$res cost: ";
        print $building_info->{'upgrade'}->{'cost'}->{$res};
        #$costs{$_} = $building_info->{'upgrade'}->{'cost'}->{$_};
        print "\n";
<<<<<<< HEAD
        my $gap = $planet_data->{$res."_stored"} - $building_info->{'upgrade'}->{'cost'}->{$res};
        if ($gap < 0){
            print "You can't afford that. ($res: $gap) \n";
            my $hours = abs($gap) / $planet_data->{$res."_hour"};
=======
        my $gap = $status->{'body'}->{$res."_stored"} - $building_info->{'upgrade'}->{'cost'}->{$res};
        if ($gap < 0){
            print "You can't afford that. ($res: $gap) \n";
            my $hours = abs($gap) / $status->{'body'}->{$res."_hour"};
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182
            my $seconds = int($hours * 60 * 60 );
            if ($sleep < $seconds){
                $sleep = $seconds;
            }
            
        }
    }
    if ($sleep > 0){
        print "Sleeping until resources available ($sleep seconds)\n";
        sleep $sleep;
    }
    $sleep = 0 ;

    # Finally. In theory, we can now build. Fire off a level check for the
    # hell of it. IF it fails, we just go back through this sub anyway, so no
    # big deal, but we really want to make sure it hasn't levelled via other
    # means while we were asleep. I really should check everything else, but
    # like I say, we're just going to go back into the loop.
    # TODO Oh, build queue. If something goes wrong here, we should check the
    # build queue and sleep until something finishes.
<<<<<<< HEAD
    $building_info = $laluna->view_building($id);
    if ($building_info->{'level'} < $lev){
        my $status = $laluna->{'OBJECTS'}->{'buildings'}->{$id}->upgrade($id); 
        if ($status->{'building'}->{'pending_build'}){
            return ($status->{'building'}->{'level'} +1);
=======
    $response = $laluna->{'OBJECTS'}->{'buildings'}->{$id}->view();
    $status = $response->{'status'};
    $building_info = $response->{'building'};
    if ($building_info->{'level'} < $lev){
        my $status = $laluna->{'OBJECTS'}->{'buildings'}->{$id}->upgrade($id); 
        if ($status->{'building'}->{'pending_build'}){
            return $status->{'building'}->{'level'};
>>>>>>> 30f2c457021c1d209dca95712de6f9adb8d6e182
        }else{
            #Kick it back to the controller, but we need some way to break out
            #of it.
            return 0;
        }
    }else{
        return $building_info->{'level'};
    }



}


=head1 SYNOPSIS

This one, in theory, lets you queue multiple levels for a building to build.
It's untested, but pretty friendly - go ahead and try it. It slees a lot, and it'll prompt you for most decisions.

=head1 AUTHOR

Jai Cornes, E<lt>solitaire@tygger.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jai Cornes

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


