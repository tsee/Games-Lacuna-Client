package Games::Lacuna::Cache;
use utf8;
use strict;
use warnings;
use Games::Lacuna::Client;
use YAML::Any qw(LoadFile DumpFile);
use Data::Dumper;


sub new {
    my $class = shift;
    my %opt = @_;
    my $self = {};
    $self->{'CLIENT'} = Games::Lacuna::Client->new( cfg_file => $opt{'cfg_file'},
                                                   #  debug    => 1,
                                                  );

    my $refresh = $opt{'refresh'};
    $self->{'debug'} = $opt{'cache_debug'} || 0;
    $self->{'CACHE_FILE'} = $opt{'cache_file'} || "empire_cache2.dat";
    $self->{'CACHE_TIME'} = $opt{'cache_time'} || 25*60;
    #Ships move faster than buildings. *nod*
    $self->{'CACHE_TIME_SHIPS'} = $opt{'cache_time_ships'} || 10*60;
    # We cache building objects to make life easier later.

    $self->{'OBJECTS'} = ();
    $self->{'EMPIRE'} = $self->{'CLIENT'}->empire;
    $self->{'DATA'} = (); # Stores the "empire" block from a status response.
    $self->{'SESSION_CALLS'} = 0;
    bless($self,$class);
    $self->debug("Using cache file: $self->{'CACHE_FILE'}");

    $self->load_data($refresh);
    
    
    return $self;


}

sub load_data {
    # Replace the return with just updating $self->{'DATA'}
    my ($self, $force_refresh) = @_;
    if ($force_refresh){
        $self->{'DATA'} = {};
    }
    $self->debug( "Loading Empire data... ");
    if ($force_refresh || !(-e $self->{'CACHE_FILE'})){
        # $self->{'DATA'} is undef, so we should be able to call this and it
        # will hit up the server.
        $self->debug( "Forcing refresh in load_data ...");
        $self->refresh_data("empire");
    }
    $self->{'DATA'} = YAML::Any::LoadFile($self->{'CACHE_FILE'});

}

sub empire_data{
    my ($self, $refresh) = @_;
    if ($refresh){
        $self->refresh_data('empire');
    }
    return $self->{'DATA'}->{'empire'};

}

sub force_reload{
    my $self = shift;
    $self->load_data(1);

}
sub planet_data{
    my ($self, $planet_id, $refresh) = @_;
    return $self->body_data($planet_id, $refresh);
}

sub body_data{
    my ($self, $body_id, $refresh) = @_;
    if ($refresh){
        $self->refresh_data("bodies", $body_id);
    }

    if ($body_id){
        return $self->{'DATA'}->{'bodies'}->{$body_id};
    }else{
        # Really just a convenience - you should call by id 
        return $self->{'DATA'}->{'bodies'};
    }

}

sub building_data{
    my ($self, $building_id, $refresh) = @_;
    # What really kills a client is fetching full data when we can live with
    # the data from $planet
    # Let the client tell us if it really needs full data 
    if ($refresh){
        $self->refresh_data("buildings", $building_id);
    }
    #
    return $self->{'DATA'}->{'buildings'}->{$building_id};

}

# The "view" methods are a wrapper around Client objects - where we really
# need current data, but still want to cache. They're probably not a *good*
# idea - the extrapolation means we have pretty current data, but they're
# handy for things like build queues
sub view_planet{
    my ($self, $id) = @_;
    my $object = $self->{'OBJECTS'}->{'bodies'}->{$id};
    # Again, we call view buildings so that *all* data is current. 
    my $response = $object->view_buildings();
    $self->{'SESSION_CALLS'} += 1;
    $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");
    $self->cache_response("body", $response);
    return $self->{'DATA'}->{'bodies'}->{$id};

}

sub view_building{
    my ($self, $id) = @_;
    my $object = $self->get_building_object($id);
    my $response = $object->view();
    $self->{'SESSION_CALLS'} += 1;
    $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");
    $self->cache_response("building", $response);
    return $self->{'DATA'}->{'buildings'}->{$id};

}

sub get_building_object{
    my ($self, $id) = @_;
    if (! $self->{'OBJECTS'}->{'buildings'}->{$id}){
        my $pattern = $self->{'DATA'}->{'buildings'}->{$id}->{'url'};
        $pattern =~ s|^/||;
        $self->{'OBJECTS'}->{'buildings'}->{$id} =  $self->{'CLIENT'}->building(type => $pattern, id => $id); 

    }
    return $self->{'OBJECTS'}->{'buildings'}->{$id};
}
sub list_planets{
    my ($self, $refresh) = @_;
    if ($refresh){
        $self->refresh_data('empire');
    }
    return $self->{'DATA'}->{'empire'}->{'planets'};
}

#sub list_buildings{
#    my ($self, $filters) = @_;
#    my @results;
#    foreach my $planet ($self->{'DATA'}){
#    }
#}

#sub list_ships_on_planet{
    #my ($self, $planet, $filters) = @_;
    # No need to refresh all the building data
    #my @b_filters = ("spaceport");
    #my @results;

    #foreach my $sp ($self->list_buildings_on_planet($planet, \@b_filters)){
        #push (@results, $self->list_ships_in_building($sp, $filters));
    #}
    #return @results;
#}

#sub list_ships_in_building{
    #my ($self, $building, $filters) = @_;
    #my @results;
    # In theory, the building data for the spaceport should show us this.
    #my $building_info = $self->{'DATA'}->{'buildings'}->{$building};
    #foreach my $type (@$filters){
        #push (@results, grep ($type, (keys %{$building_info->{'docked_ships'}})));
    #}

    #return @results;
#}

sub list_buildings_on_planet{
    # Pass me an arrayref of buildings to filter for. Empty arrayref, get every building
    # Returns a list of building IDs
    my ($self, $planet, $filters) = @_;
    $self->refresh_data("bodies", $planet);
    my @results;

    my $buildings  = $self->{'DATA'}->{'bodies'}->{$planet}->{'buildings'};
    #print Dumper($self->{'planet_data'}{'planets'}{$planet});
    if ($filters){
        foreach my $pattern (@$filters){
            foreach my $id (keys %$buildings){
                #print "(searching planet $planet for $pattern ...)\n"; 
                if ($buildings->{$id}->{'url'} =~ m|/$pattern|){
                    #        print "(found $pattern ($_) ...)\n"; 
                    $self->{'OBJECTS'}->{'buildings'}->{$id} =  $self->{'CLIENT'}->building(type => $pattern, id => $id); 
                    push (@results, $id);

                }
            }
        }
    }else{
        foreach my $id (keys %$buildings){
            my $pt = $buildings->{$id}->{'url'};
            $pt =~ s|^/||;
            $self->{'OBJECTS'}->{'buildings'}->{$id} =  $self->{'CLIENT'}->building(type => $pt, id => $id); 
            push (@results, $id);
        }

    }
    return @results;
}

sub refresh_data{
    my ($self, $key, $id) = @_;
    my $response;
    if ($id){
        # It'll be a building or a planet, or ships.
        my $checked = $self->{'DATA'}->{$key}->{$id}->{'last_checked'};
        if (! $checked ||  (time() - $checked) >  $self->{'CACHE_TIME'}
             || ($self->{'DATA'}->{$key}->{$id}->{'response_type'} eq "partial")){
            # We're stale or we don't exist or we were only partial in the
            # first place. 
            #print "Stale data for $key!\n";
            my $client_object = $self->{'OBJECTS'}->{$key}->{$id};
            if ($key =~ m/bodies/){
                $client_object ||= $self->{'CLIENT'}->body("id"=> $id);
                # We might as well view buildings, then we have a summary
                # for those as well.
                $response = $client_object->get_buildings();
                $self->debug( "=== RPC CALL - refresh $key $id ! ===\n");
                $self->{'SESSION_CALLS'} += 1;
                $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");
                $self->cache_response("body",$response);
            }elsif($key =~ m/buildings/){
                # This is the hard part. IF the object doesn't exist, we
                # make one from the id. If the id doesn't exist, we get it
                # from the body.
                if (! $client_object){
                    # We need type to make an object.
                    my $type = $self->{'DATA'}->{$key}->{$id}->{'type'};
                    # If we have no type, then we've never seen the
                    # building before, which is unlikely.
                    $client_object = $self->{'CLIENT'}->building("type" => $type,
                                                                 "id" => $id);
                }
                $self->debug( "=== RPC CALL - refresh $key $id ! ===\n");
                $self->{'SESSION_CALLS'} += 1;
                $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");
                $response = $client_object->view();
                $self->cache_response("building",$response);
            
            }
            # Store the new object for later.
            $self->{'OBJECTS'}->{$key}->{$id} = $client_object;
        }else{
            # We have freshish data, but no harm tweaking it.
            $self->extrapolate();
        }
    }else{
        #We're empire or we're refreshing all bodies (why would you do that?).
        if ($key =~ m/empire/){
            my $checked = $self->{'DATA'}->{$key}->{'last_checked'};
            if (!$checked ||  (time() - $checked) >  $self->{'CACHE_TIME'}){
                # We're stale or we don't exist. 
                # Only force a write when we do this top level, not for every
                # bloody planet
                $self->debug( "Stale in empire - refreshing ");
                $self->debug( "=== RPC CALL - refresh Empire ! ===\n");
                $self->{'SESSION_CALLS'} += 1;
                $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");

                $response = $self->{'EMPIRE'}->get_status();
                $self->cache_response("empire",$response);
            }else{
                $self->extrapolate();
            }
        }else{
            # There's no real reason to refresh data for every planet. You
            # have the planet ids, you can work on them directly. If you need
            # all the planets, use a foreach and cache them that way
            $self->debug( "Not yet implemented!");
        }
    }

    if ($response){
        YAML::Any::DumpFile($self->{'CACHE_FILE'}, $self->{'DATA'});
    }
}

sub cache_response {
    # TODO - refactor. This is a little ugly because of the 2 levels of
    # response 
    my ($self, $type, $response) = @_;
    #print "Caching response:\n";
    #print Dumper($response);
    if ($response->{'status'}->{'empire'}){
        $self->{'DATA'}->{'empire'} = $response->{'status'}->{'empire'};
        $self->{'DATA'}->{'empire'}->{'last_checked'} = time();
    }

    if ($response->{'status'}->{'body'}){
        # Need to store the building hash temporarily then re-enable this
        my $id = $response->{'status'}->{'body'}->{'id'};
        foreach (%{$response->{'status'}->{'body'}}){
            $self->{'DATA'}->{'bodies'}->{$id}->{$_} = $response->{'status'}->{'body'}->{$_};
        }
        $self->{'DATA'}->{'bodies'}->{$id}->{'response_type'} = "full";
        $self->{'DATA'}->{'bodies'}->{$id}->{'last_checked'} = time();
    }

    if ($type eq "body"){
        # We have a body and the associated buildings. Store building data in
        # {'buildings'} by id, put the ids in {'body'}{'buildings'} and make
        # objects
        my $body_id = $response->{'status'}->{'body'}->{'id'};
        $self->{'DATA'}->{'bodies'}->{$body_id} = $response->{'status'}->{'body'};
        $self->{'DATA'}->{'bodies'}->{$body_id}->{'response_type'} = "full";
        $self->{'DATA'}->{'bodies'}->{$body_id}->{'last_checked'} = time();

        foreach my $building (keys %{$response->{'buildings'}}){
            $self->{'DATA'}->{'buildings'}->{$building} = $response->{'buildings'}->{$building};
            $self->{'DATA'}->{'buildings'}->{$building}->{'planet_id'} = $response->{'status'}->{"body"}->{'id'};
            $self->{'DATA'}->{'buildings'}->{$building}->{'response_type'} = "partial";
            $self->{'DATA'}->{'buildings'}->{$building}->{'last_checked'} = time();
            $self->{'DATA'}->{'bodies'}->{$body_id}->{'buildings'}->{$building} = $response->{'buildings'}{$building};
        }
    }elsif ($type eq "building"){
        my $id = $response->{'building'}->{'id'}; 
        $self->{'DATA'}->{'buildings'}->{$id} = $response->{'building'};
        $self->{'DATA'}->{'buildings'}->{$id}->{'response_type'} = "full";
        $self->{'DATA'}->{'buildings'}->{$id}->{'last_checked'} = time();
        foreach my $section (grep (! /empire|status/, keys %{$response})){
            # Store top level sections like ships_docked, recycle, etc
            $self->{'DATA'}->{'buildings'}->{$id}->{$section} =
                $response->{$section};
        }
    }elsif ($type =~ m/empire/){
        # Have we not already covered this?
        $self->{'DATA'}->{'empire'} = $response->{'empire'};
        $self->{'DATA'}->{'empire'}->{'last_checked'} = time();
        foreach (keys %{$response->{'empire'}->{'planets'}}){
            $self->refresh_data("bodies", $_);
        }

    }
    # GAR GAR GAR
    #foreach (keys %{$self->{'DATA'}->{'empire'}->{'planets'}}){
        #utf8::decode($self->{'DATA'}->{'empire'}->{'planets'}->{$_});
        #print "\n==\nEncoded " . $self->{'DATA'}->{'empire'}->{'planets'}->{$_} .  " in empire data\n";
        #utf8::decode($self->{'DATA'}->{'bodies'}->{$_}->{'name'});
        #print "Encoded " . $self->{'DATA'}->{'empire'}->{'planets'}->{$_} .  "in planet data \n";
    #}
    #my $fh = open(">:utf8",$self->{'CACHE_FILE'});
    #YAML::Any::DumpFile($fh, $self->{'DATA'});

}


sub extrapolate{
    my $self = shift;
    my @resources = ("water", "ore", "energy", "waste");
    foreach my $planet (keys %{$self->{'DATA'}->{'empire'}->{'planets'}}){
        my $data = $self->{'DATA'}->{'bodies'}->{$planet};
        # We don't want to update last_checked if we didn't honestly check. 
        # But if we use last_checked, we're adding to an extrapolated figure....
        my $checked = $data->{'last_extrapolated'} || $data->{'last_checked'};
        #$self->debug("Time last checked (or extrapolated): $checked \n");
        #$self->debug("Time now: " . time() . "\n");
        # Fraction of an hour
        #$self->debug("Delta: " . (time() - $checked) );
        
        my $lapsed =  (time() - $checked) / 3600;
        #$self->debug("Difference:  $lapsed of an hour \n");
        foreach my $res (@resources){
            my $add = int($data->{$res."_hour"} * $lapsed);
            $data->{$res."_stored"} = $data->{$res."_stored"} + $add;
        };
        $data->{'last_extrapolated'} = time();
    }
        YAML::Any::DumpFile($self->{'CACHE_FILE'}, $self->{'DATA'});

}

sub debug{
    my ($self, $message) = @_;
    print "$message \n" if $self->{'debug'};
}

sub remaining_capacity{
    my ($self, $planet, $res) = @_;
    $self->extrapolate();

    my $amount = $self->{'DATA'}->{'bodies'}->{$planet}->{$res."_stored"};
    my $capacity = $self->{'DATA'}->{'bodies'}->{$planet}->{$res."_capacity"};
    return $capacity - $amount; 

}
sub prop_capacity{
    my ($self, $planet, $res) = @_;
    $self->extrapolate();

    my $amount = $self->{'DATA'}->{'bodies'}->{$planet}->{$res."_stored"};
    my $capacity = $self->{'DATA'}->{'bodies'}->{$planet}->{$res."_capacity"};
    return ($amount / $capacity); 
}


sub list_trade_ships{
    my ($self, $tm_id, $refresh) = @_;
    my @ships;
    # One day, we will cache ships....
    my $obj = $self->get_building_object($tm_id);
    $self->{'SESSION_CALLS'} += 1;
    my $response = $obj->get_trade_ships();
    #print Dumper($response);
    foreach (@{$response->{'ships'}}){
        push (@ships, $_);
    }
    return @ships;

}

sub resource_details{
    my ($self, $planet_id, $resource_type) = @_;

    my $breakdown = $self->{'DATA'}->{'planets'}->{$planet_id}->{'breakdowns'}->{$resource_type};

    if (! $breakdown ){
        my @buildings = $self->list_buildings_on_planet($planet_id, ["trade"]);
        if (@buildings){
            my $obj = $self->get_building_object($buildings[0]);
            $self->{'SESSION_CALLS'} += 1;
            my $response = $obj->get_stored_resources();
            $breakdown = $self->parse_resource_breakdown($response->{'resources'}, $resource_type); 

        }
    }
    return $breakdown;

}

sub parse_resource_breakdown{
    my ($self, $data, $type) = @_;

    my @foods = (
                 "algae",
                 "apple",
                 "bean",
                 "beetle",
                 "bread",
                 "burger",
                 "cheese",
                 "chip",
                 "cider",
                 "corn",
                 "fungus",
                 "lapis",
                 "meal",
                 "milk",
                 "pancake",
                 "pie",
                 "potato",
                 "root",
                 "shake",
                 "soup",
                 "syrup",
                 "wheat",
                 );
    my @ores = (
                "anthracite",
                "bauxite",
                "beryl",
                "chalcopyrite",
                "chromite",
                "fluorite",
                "galena",
                "goethite",
                "gold",
                "gypsum",
                "halite",
                "kerogen",
                "magnetite",
                "methane",
                "monazite",
                "rutile",
                "sulfur",
                "trona",
                "uraninite",
                "zircon",
               );
    foreach my $food( @foods){
        $self->{'DATA'}->{'breakdowns'}->{'food'}->{$food} = $data->{$food};
    }
    foreach my $ore( @ores){
        $self->{'DATA'}->{'breakdowns'}->{'ore'}->{$ore} = $data->{$ore};
    }

return $self->{'DATA'}->{'breakdowns'}->{$type};

}

sub count_calls{
    my $self = shift;
    $self->debug( "=== SESSION CALLS: $self->{'SESSION_CALLS'} ! ===\n");
    return $self->{'SESSION_CALLS'};
}
1;
=pod

=head1 NAME

Games::Lacuna::Cache - a caching mechanism for Games::Lacuna::Client

=head1 SYNOPSIS

    use Games::Lacuna::Cache;
    my $lacuna = Games::Lacuna::Cache->new(
                                           'cfg_file' => "/path/to/lacuna.yml",
                                           'cache_file' => "/path/to/lac_cache.dat",
                                           'cache_debug' => 1,
                                           'refresh' => 0
                                          );

    my $empire_data = $lacuna->empire_data();
    my $planet_data = $lacuna->planet_data($planet_id, $refresh);

=head1 DESCRIPTION

This module provides a caching mechanism for the C<L<Games::Lacuna::Client>>
package.

=head1 METHODS

=head2 C<new>

    my $lacuna = Games::Lacuna::Cache->new( $refresh );

If C<$refresh> is defined, the Cache will force a refresh of the data.

=head2 C<empire_data([$refresh])>

Returns top level empire data

=head2 C<planet_data([$planet_id], [$refresh])>

Returns planet data for C<$planet_id>, or all bodies if you leave off the id.
At the moment,

=head2 C<body_data([$body_id], [$refresh])>

Ditto.

These should work pretty much as you expect. Cache stores partial 
information if it has it, and full information if you request it. 
That's because a lot of high level calls return a bit of data about 
the next level down (Empire gives planets, Body gives buildings, etc). 
So we store the partial to avoid hitting up a full call when all you 
want is the id. So C<empire_data> will give you full empire data and partial
planets (just ID and name). C<Planet_data> will give you full data on the
planet and partial (though fairly good) data on the buildings.
C<building_data> will give you full info on the building. 

=head2 C<building_data([$building_id], [$refresh])>

This might not work as you expect. By default, when we call body_data, 
we store partial info on buildings from a C<< body->get_buildings() >> request. 
That's generally enough for pending build, recycling, etc. Calling
building data with the refresh flag set will give you full info on that
building.  

The data structure returned from a full request consists of the main 
hash returned by the C<< object->view() >> call, *and* other top level 
structures in the response.  So if you call 

    my $spaceport = $lacuna->building_data($spaceport),

you'll get C<< $spaceport->{'id'} >>, C<< $spaceport->{'waste_hour'} >>, etc, but 
you'll also get C<< $spaceport->{'docked_ships'} >>. Similarly,
C<< $recycler->{'recycle'} >> if it's in the middle of one. 

=head2 NB REFRESH FLAG

The "I<refresh>" flag may not work quite as you expect. It doesn't 
guarantee fresh info. It guarantees full data less than 25 minutes old 
(or whatever you set I<CACHE_TIME> to). That's somewhat counterintuitive,
and I should probably call it the "I<full>" flag, but for the moment, this 
is what you get. The resource extrapolation works pretty well, so if you
call "I<refresh>" on a building for which we already have full info, you'll
get that full info, with extrapolated resource values, but it might be a
little old. If you absolutely must have up to the second data, there are
convenience methods to call:

=head2 C<view_planet($planet_id)>

Z<>

=head2 C<view_building($building_id)>

These are wrappers around the C<< body->view_buildings >> (because that gives
building info B<and> full planet info) and C<< building->view() >>
client methods.
These guarantee you up-to-the-second information about a planet or
building, and they also cache the info.

=head2 C<list_buildings_on_planet($planet, [$array_ref])>

    my @filters = ("spaceport");
    my @buildings = $lacuna->list_buildings_on_planet($planet, \@filters);

C<$planet> will be a planet id. C<foreach my $planet (keys %$planet_data)> from
above will do.


C<@filters> needs to contain valid building types of the kind found in a 
building url - "I<wasterecycling>" or "I<spaceport>". Feel free to implement a 
look up table for "I<Space Port>" and "I<Trash Compactor>" :)

The method returns a list of building ids, but it also creates client 
objects in the I<Cache OBJECT> structure. So then you could say

    foreach $building (@recyclers){
        my $object = $lacuna{'OBJECTS'}->{'buildings'}->{$building};
        $object->recycle();

or any similar client method. Don't use the object for view methods,
though - use the helper methods above so data is cached (and actually
just use cached data where you can)

Note objects do not persist between script calls, and are not shared 
between scripts.

=head1 DATA

=head2 OBJECTS

C<< $lacuna->{'OBJECTS'}->{'buildings'} >>
and
C<< $lacuna->{'OBJECTS'}->{'bodies'} >>

Stored by id. This just means you don't have to toss around the objects all 
the time.

C<< $lacuna->{'OBJECTS'}->{$type}->{$id}->method(); >>
should always work.


I think that's about it.

=head1 CAVEATS

It may stomp on disk data, but scripts should play friendly with each other. 
See how it goes.

You know the drill. Don't use it to run Fusion Power plants. I<Oh, wait....>

=head1 AUTHOR

Jai Cornes, E<lt>solitaire@tygger.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jai Cornes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.
