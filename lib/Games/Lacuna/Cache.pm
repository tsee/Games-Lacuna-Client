package Games::Lacuna::Cache;
use strict;
use warnings;
use Games::Lacuna::Client;
use YAML::Any qw(LoadFile DumpFile);
use Data::Dumper;
binmode STDOUT, ":utf8";


sub new {
    my $cfg_file =  'lacuna.yml';
    my $self = {};
    bless($self);
    $self->{'CLIENT'} = Games::Lacuna::Client->new( cfg_file => $cfg_file,
                                                    # debug    => 1,
                                                  );

    my $refresh = $ARGV[0];
    $self->{'CACHE_FILE'} = "empire_cache2.dat";
    $self->{'CACHE_TIME'} = 25*60;
    # We cache building objects to make life easier later.

    $self->{'OBJECTS'} = ();
    $self->{'EMPIRE'} = $self->{'CLIENT'}->empire;
    $self->{'DATA'} = (); # Stores the "empire" block from a status response.
    $self->load_data($refresh);
    
    
    return $self;


}

sub empire_data{
    my ($self, $refresh) = @_;
    $self->refresh_data('empire');
    return $self->{'DATA'}->{'empire'};

}

sub planet_data{
    my ($self, $planet_id, $refresh) = @_;
    return $self->body_data($planet_id, $refresh);
}

sub body_data{
    my ($self, $body_id, $refresh) = @_;
    if ($body_id){
        $self->refresh_data("bodies", $body_id);
        return $self->{'DATA'}->{'bodies'}->{$body_id};
    }else{
        # Really just a convenience - you should call by id 
        $self->refresh_data('empire');
        return $self->{'DATA'}->{'empire'}->{'planets'};
    }

}

sub building_data{
    my ($self, $building_id, $refresh) = @_;
    $self->refresh_data("buildings", $building_id);
    return $self->{'DATA'}->{'buildings'}->{$building_id};

}


sub force_refresh{
    my $self = shift;

}

sub load_data {
    # Replace the return with just updating $self->{'DATA'}
    my ($self, $force_refresh) = @_;
    print "Loading Empire data... \n";
    my $pr;
    my $hr;
    if ($force_refresh || !(-e $self->{'CACHE_FILE'})){
        # $self->{'DATA'} is undef, so we should be able to call this and it
        # will hit up the server.
        print "Forcing refresh in load_data ...\n";
        $self->refresh_data("empire");
    }
    $self->{'DATA'} = YAML::Any::LoadFile($self->{'CACHE_FILE'});

}

sub list_planets{
    my $self = shift;
    $self->refresh_data('empire');
    return $self->{'DATA'}->{'empire'}->{'planets'};
}

#sub list_buildings{
#    my ($self, $filters) = @_;
#    my @results;
#    foreach my $planet ($self->{'DATA'}){
#    }
#}


sub list_buildings_on_planet{
    # Pass me an arrayref of buildings to filter for. Empty arrayref, get every building
    # Returns a list of building IDs
    my ($self, $planet, $filters) = @_;
    my @results;

    my $buildings  = $self->{'DATA'}{'bodies'}{$planet}{'buildings'};
    #print Dumper($self->{'planet_data'}{'planets'}{$planet});
    if ($filters){
        foreach my $pattern (@$filters){
    #        print "(searching planet $planet for $pattern ...)\n"; 
            foreach (grep {$buildings->{$_}{'url'} eq "/$pattern"} keys %$buildings){
    #        print "(found $pattern ($_) ...)\n"; 
              $self->{'OBJECTS'}->{'buildings'}->{$_} =  $self->{'CLIENT'}->building(type => $pattern, id => $_); 
            push (@results, $_);

            }
        }
    }else{
        foreach (keys %$buildings){
            my $pt = $buildings->{$_}->{'url'};
            $pt =~ s|^/||;
            $self->{'OBJECTS'}->{'buildings'}->{$_} =  $self->{'CLIENT'}->building(type => $pt, id => $_); 
            push (@results, $_);
        }

    }
    return @results;
}

sub refresh_data{
    my ($self, $key, $id) = @_;
    my $response;
    if ($id){
        # It'll be a building or a planet.
        if ( (time() - $self->{'DATA'}->{$key}->{$id}->{'last_checked'}) >  $self->{'CACHE_TIME'}
             || ($self->{'DATA'}->{$key}->{$id}->{'response_type'} eq "partial")){
            # We're stale or we don't exist or we were only partial in the
            # first place. 
            print "Stale data for $key!\n";
            my $client_object = $self->{'OBJECTS'}->{$key}->{$id};
            if ($key =~ m/bodies/){
                $client_object ||= $self->{'CLIENT'}->body("id"=> $id);
                # We might as well view buildings, then we have a summary
                # for those as well.
                #print "=== MAKING CALL TO SERVER! ===\n";
                $response = $client_object->get_buildings();
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
                #print "=== MAKING CALL TO SERVER! ===\n";
                $response = $client_object->view();
                $self->cache_response("building",$response);
            }
            # Store the new object for later.
            $self->{'OBJECTS'}->{$key}->{$id} = $client_object;
        }
    }else{
        #We're empire or we're refreshing all bodies (why would you do that?).
        if ($key =~ m/empire/){
            if ( (time() - $self->{'DATA'}->{$key}->{'last_checked'}) >  $self->{'CACHE_TIME'}){
                # We're stale or we don't exist. 
                # Only force a write when we do this top level, not for every
                # bloody planet
                print "Stale in empire - refreshing \n";
                #print "=== MAKING CALL TO SERVER! ===\n";
                $response = $self->{'EMPIRE'}->get_status();
                $self->cache_response("empire",$response);
            }
        }else{
            # There's no real reason to refresh data for every planet. You
            # have the planet ids, you can work on them directly. If you need
            # all the planets, use a foreach and cache them that way
            print "Not yet implemented!";
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
    print "Caching response:\n";
    #print Dumper($response);
    print "===================================\n";
    if ($response->{'status'}->{'empire'}){
        $self->{'DATA'}->{'empire'} = $response->{'status'}->{'empire'};
        $self->{'DATA'}->{'empire'}->{'last_checked'} = time();
    }
    if ($response->{'status'}->{'body'}){
        my $id = $response->{'status'}->{'body'}->{'id'};
        $self->{'DATA'}->{'bodies'}->{$id} = $response->{'status'}->{'body'};
        $self->{'DATA'}->{'bodies'}->{$id}->{'response_type'} = "partial";
        $self->{'DATA'}->{'bodies'}->{$id}->{'last_checked'} = time();
    }

    if ($type eq "body"){
        # We have a body and the associated buildings. Store building data in
        # {'buildings'} by id, put the ids in {'body'}{'buildings'} and make
        # objects
        my $body_id = $response->{'status'}->{'body'}->{'id'};
        $self->{'DATA'}->{'bodies'}->{$body_id}->{'response_type'} = "full";

        foreach my $building (keys %{$response->{'buildings'}}){
                    $self->{'DATA'}->{'buildings'}->{$building} = $response->{'buildings'}->{$building};
                    $self->{'DATA'}->{'buildings'}->{$building}->{'response_type'} = "partial";
                    $self->{'DATA'}->{'buildings'}->{$building}->{'last_checked'} = time();
                    $self->{'DATA'}->{'bodies'}->{$body_id}->{'buildings'}->{$building} = $response->{'buildings'}{$building};
        }
    }elsif ($type eq "building"){
        my $id = $response->{'building'}->{'id'}; 
        $self->{'DATA'}->{'buildings'}->{$id} = $response->{'building'};
        $self->{'DATA'}->{'buildings'}->{$id}->{'response_type'} = "full";
        $self->{'DATA'}->{'buildings'}->{$id}->{'last_checked'} = time();
    }elsif ($type =~ m/empire/){
        # Have we not already covered this?
        $self->{'DATA'}->{'empire'} = $response->{'empire'};
        $self->{'DATA'}->{'empire'}->{'last_checked'} = time();
    }

}

1;

=pod

=head1 NAME

Games::Lacuna::Cache - a caching mechanism for Games::Lacuna::Client

=head1 SYNOPSIS

use Games::Lacuna::Cache;
my $lacuna = Games::Lacuna::Cache->new();
my $planet_data = $lacuna->planet_data($planet_id);

or 
my $lacuna = Games::Lacuna::Cache->new(1); 

to force the data to refresh.

=head1 DESCRIPTION
This module provides a caching mechanism for the Games::Lacuna::Client
package.

=head1 METHODS

=head2 new

my $lacuna = Games::Lacuna::Cache->new( $refresh );

If $refresh is defined, the Cache will force a refresh of the data.

=head2 empire_data()
Returns top level empire data

=head2 planet_data([$planet_id])
Returns planet data for $planet_id, or all bodies if you leave off the id.

=head2 body_data([$body_id])
Ditto.
=head2 building_data([$building_id])
And roughly ditto

These should work pretty much as you expect. Cache stores partial information
if it has it, and full information if you request it. That's because a lot of
high level calls return a bit of data about the next level down (Empire gives 
planets, Body gives buildings, etc). So we store the partial to avoid hitting
up a full call when all you want is the id. Expressly asking by id *should*
give you full info.

=head2 list_planets()
returns a very basic hash of planet_id => name

=head2 list_buildings_on_planet($planet, [$array_ref])

    my @filters = ("spaceport");
    my @buildings = $lacuna->list_buildings_on_planet($planet, \@filters);

$planet will be a planet id. foreach my $planet (keys %$planet_data) from above will do. 


@filters needs to contain valid building types of the kind found in a building url - "wasterecycling" or "spaceport". Feel free to implement a look up table for "Space Port" and "Trash Compactor" :)

The method returns a list of building ids, but it also creates client objects
in the Cache OBJECT structure. So then you could say
foreach $building (@buildings){

    my $object = $lacuna{'OBJECTS'}->{'buildings'}->{$building};
    $object->view();

or any similar client method.

Note objects do not persist between script calls, and are not shared between
scripts. 

=head1 DATA 

=head2 OBJECTS

$lacuna->{'OBJECTS'}->{'buildings'}
and
$lacuna->{'OBJECTS'}->{'bodies'}

Stored by id. This just means you don't have to toss around the objects all the time. 
$lacuna->{'OBJECTS'}->{$type}->{$id}->method();
should always work.


I think that's about it.

=head1 CAVEATS

It may stomp on disk data, but scripts should play friendly with each other. See how it goes.

head1 AUTHOR

Jai Cornes, E<lt>solitaire@tygger.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jai Cornes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


