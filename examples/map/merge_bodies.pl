#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long qw(GetOptions);
use YAML::Any ();
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

our $DbFile = 'map.sqlite';
our $ImportFile = 'import.sqlite';

my $bodies;

GetOptions(
  'd|dbfile=s' => \$DbFile,
  'i|importfile=s' => \$ImportFile,
);

LacunaMap::DB->import($DbFile);

my $old_bodies = LacunaMap::DB->selectall_hashref( q{select * from bodies}, 'sql_primary_id' );

for my $pk ( keys %{ $old_bodies } )
{
    my $item = $old_bodies->{$pk};
    delete $item->{sql_primary_id};
    $bodies->{ $item->{star_id}}{ $item->{name} } = $item;
}

LacunaMap::DB->import($ImportFile);

my $new_bodies = LacunaMap::DB->selectall_hashref( q{select * from bodies}, 'sql_primary_id' );

# reset back to the original DB
LacunaMap::DB->import($DbFile);

for my $pk ( keys %{ $new_bodies } )
{
    my $new = $new_bodies->{$pk};
    delete $new->{sql_primary_id};
    my ( $star_id, $name ) = ( $new->{star_id}, $new->{name} );
    my $old = $bodies->{ $star_id }{ $name };
    if ( exists $bodies->{ $star_id }{ $name } )
    {
        process( $old, $new );
        $bodies->{ $star_id }{ $name } = $old;
    }
    else
    {
        $bodies->{ $star_id }{ $name } = $new;
    }
    updater( $bodies->{ $star_id }{ $name } );
}

sub updater
{
    my $res = shift;
    my $bodies = LacunaMap::DB::Bodies->select(
        'where star_id = ? and name = ?', $res->{star_id}, $res->{name}
    );
    if ( not @$bodies )
    {
        # new entry
        delete $res->{updated};
        warn "no bodies found in DB, adding\n", Dumper( $res );
        LacunaMap::DB::Bodies->new(
            id          => $res->{id},
            name        => $res->{name},
            x           => $res->{x},
            y           => $res->{y},
            star_id     => $res->{star_id},
            orbit       => $res->{orbit},
            type        => $res->{type},
            size        => $res->{size},
            empire_id   => $res->{empire_id},
        )->insert;
    }
    elsif ( @$bodies == 1 )
    {
        if ( $res->{updated} )
        {
            delete $res->{updated};
            warn "updating\n", Dumper( $res );
            for ( $bodies->[0] )
            {
                $_->delete();
                $_->name( $res->{name} );
                $_->x( $res->{x} );
                $_->y( $res->{y} );
                $_->star_id( $res->{star_id} );
                $_->orbit( $res->{orbit} );
                $_->type( $res->{type} );
                $_->size( $res->{size} );
                # $_->empire_id( $res->{empire_id} ); # doesn't work
                $_->{empire_id} = $res->{empire_id};
                $_->insert();
            }
        }
    }
    else
    {
        warn "Found multiple bodies for the given new colony";
        return;
    }
}

sub process
{
    my ( $old, $new ) = @_;

    for my $what qw( id x y orbit type size empire_id )
    {
        if ( ! defined $old->{ $what } && defined $new->{ $what } )
        {
            warn "$what didn't exist in old\n", "old: ", Dumper( $old ), "\nnew: ", Dumper( $new ), "\n";
            $old->{ $what } = $new->{ $what };
            $old->{updated}{ $what } = 1;
        }
        elsif ( defined $old->{ $what } && defined $new->{ $what } )
        {
            if ( ( $what eq 'type' && $old->{type} ne $new->{type} ) || ( $what ne 'type' && $old->{ $what } != $new->{ $what } ) )
            {
                error( $what, $old, $new );
            }
        }
    }
}

sub error
{
    my ( $what, $old, $new ) = @_;
    die "$what doesn't match!\nold:", Dumper( $old ), "\nnew:", Dumper( $new ), "\n";
}
