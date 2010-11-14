#!/usr/bin/perl
use strict;
use warnings;
use Games::Lacuna::Cache;
use Data::Dumper;


my $didyoureadthedocumentation = 1;

if ($didyoureadthedocumentation){
    print "Please read the script before running! \n";
    exit;
}

my $refresh = $ARGV[0] || 0;
#print "Refresh: $refresh \n";
my $hard_thresh = 0.9; # For colonies producing negative ore - keep some space
my $cap_thresh = 0.5;
my $t_thresh = 8;
my $recyc_prop = 0.5;
my $hard_prop = 0.1;
#Let's get rid of one thing to pass around and convert.

binmode STDOUT, ":utf8";
my $pattern = "wasterecycling";
my $next_recycle = 1;
my $laluna = Games::Lacuna::Cache->new($refresh);

my $empire_data = $laluna->empire_data();

#print Dumper(%planet_data);
#exit;



foreach my $planet (keys %{$empire_data->{'planets'}}){
    my $status = $laluna->planet_data($planet);
    #print Dumper($planet);
    my $name = $status->{'name'};
    utf8::decode($name);

    print "\n+=========== $name ============\n";

    my $cur_waste = $status->{'waste_stored'} . "/" . $status->{'waste_capacity'}; 
    my $cur_waste_n = $status->{'waste_stored'} / $status->{'waste_capacity'}; 
    if ($cur_waste_n > $cap_thresh){

        print "| Over threshold ($cur_waste) ";
        if ($status->{'waste_hour'} > 0 ){
            print "and positive growth - recycling\n";
            my $response = schedule_recycle($planet, $status, $recyc_prop); 
            print "| $response \n";
        }else{
            if ($cur_waste_n > $hard_thresh){
                print " and over hard threshold - recycling\n";
            my $response = schedule_recycle($planet, $status,  $hard_prop); 
            print "| $response \n";
            }else{
                print "but negative growth - NOT recycling\n";
            }
        }
    }else{
        print "| Under threshold ($cur_waste) - not recycling. \n";
            my $recyc = ($status->{'waste_capacity'} - $status->{'waste_stored'}) / $status->{'waste_hour'};

        if ($status->{'waste_hour'} > 0){
            print "| Recycle required in $recyc hours. \n";
            if ($recyc < $next_recycle ){
                $next_recycle = $recyc;
            }
        }else{
            if (abs($recyc) < 8){
                print "| Only ". abs($recyc) . " hours of waste - consider
                    shipping!\n";
            }
        }

    }
    print "|\n+========= End $name ==========\n\n";
}
print "Next recycle should occur in $next_recycle hours\n\n";

#print Dumper(%planet_data);
#
sub schedule_recycle{
    use vars qw($laluna);
    my ($planet, $status, $prop) = @_;
    my %storage;
    my %weight;
    my $w_total;
    my $r_cap;
    my %recyc;
    my $waste = int($status->{'waste_stored'} * $prop);
    my %recyclers;
    # Check for an available recycler.
    #
    my @filters = ("wasterecycling");
    foreach ($laluna->list_buildings_on_planet($planet, \@filters)){
        my $re = $laluna->{'OBJECTS'}->{'buildings'}->{$_};
        print "| Found recycler $re->{'building_id'} \n";
        my $rec = $re->view();
        # Consider writing to cache
        $status = $rec->{'status'}->{'body'};
        #print Dumper($rec->{'recycle'});
        if ($rec->{'recycle'}{'seconds_remaining'}){
            print "| - Recycler not available (" .
                $rec->{'recycle'}{'seconds_remaining'}. " remaining) \n";
        }else{
            print "| Recycler is go! \n";
            $recyclers{$rec->{'building'}->{'id'}} = {"object" =>  $re,
                "rate" => $rec->{'recycle'}{'seconds_per_resource'},
                "cap" => $rec->{'recycle'}{'max_recycle'},
            };
            $r_cap += $rec->{'recycle'}{'max_recycle'},
        }


    }

    if (scalar(keys %recyclers) == 0){
        return " No available recyclers. Try again later. ";
    }


    foreach('water', 'ore', 'energy'){
        #print Dumper($status);
        $storage{$_}{'level'} = $status->{$_.'_stored'} / $status->{$_.'_capacity'};
        #print " $_ level:  $storage{$_}{'level'}\n";
        $weight{$_} = int((1 - $storage{$_}{'level'}) * 10);
        $w_total += $weight{$_};

    }

    while ($waste > $r_cap){
        $waste *= 0.9;
    }

    foreach my $rec (keys %recyclers){
        print "| Assigning to recycler $rec ...\n";
        my $assigned = $waste / scalar(keys %recyclers);
        while ($assigned > $recyclers{$rec}{"cap"}){
            $assigned *= 0.9;
        }

        foreach my $res (keys %weight){
            $recyclers{$rec}{$res} = int(($assigned/$w_total) * $weight{$res});
            print "| -- Recycling $recyclers{$rec}{$res} units of $res. \n"
        }


        #XXX TODO In theory, this returns body status, which allows us to
        #refresh planet_data.
        my $response = $recyclers{$rec}{'object'}->recycle($recyclers{$rec}{'water'}, $recyclers{$rec}{'ore'}, $recyclers{$rec}{'energy'});
        print "| Recycling. Time remaining: " . $response->{'recycle'}{'seconds_remaining'}
        . "\n";
        $status = $response->{'status'};
    }

    return "Reycling done";


}





#sub list_all_buildings {
#    use vars qw(%building_types);
#    my ($planets_by_name, $pattern) = @_;
#    my @results;

#    my $bt = $building_types{$pattern};
#    print "Building type: $bt \n";

#    foreach my $planet (values %$planets_by_name) {
#        push @results, list_buildings_by_planet($planet, $bt, $pattern);
#    }
#    return @results;
#}

#sub list_buildings_by_planet{
#    my($planet, $bt, $pattern) = @_;
#    my @results;

#    my %buildings = %{ $planet->get_buildings->{buildings} };

#    my @b = grep {$buildings{$_}{name} eq $pattern} keys %buildings;
#    push @results, map  { $client->building(type => $bt, id => $_) } @b;
#    return @results;

#}
=head1 SYNOPSIS

Use with care. 

This will find any planets with waste over a certain threshold and positive
waste generation, and automatically recycle a certain amount of their waste. 
One day I'll make it a daemon, but for now you can cron it. 

By default the threshold is 50% of waste capacity, and it will recycle 50% of
the waste. It'll split them among the recyclers it finds on the planet, and
it'll weight the recycle according to your storage. So if you're full on ore,
but low on energy, it will make more energy than ore.

Negative waste planets will still be recycled, but at a much higher threshold
(90%), and it'll only recycle 10%, just to keep a bit of room for building/
emergencies/I dunno.

Now you can delete the didyoureadthedocumentation flag ....

=head1 AUTHOR

Jai Cornes, E<lt>solitaire@tygger.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jai Cornes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


