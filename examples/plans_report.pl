#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first max));
use List::MoreUtils       qw( any none );
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();
use Games::Lacuna::Client::Types qw( get_tags building_type_from_label meta_type );
use Scalar::Util          qw( refaddr );
use Try::Tiny;

my @planets;

GetOptions(
    'planet=s@' => \@planets,
);

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
	cfg_file  => $cfg_file,
    rpc_sleep => 2,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if @planets && none { lc $name eq lc $_ } @planets;

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};

    my $buildings = $result->{buildings};

    # PPC or SC?
    my $command_url = $result->{status}{body}{type} eq 'space station'
                    ? '/stationcommand'
                    : '/planetarycommand';

    my $command_id = first {
            $buildings->{$_}{url} eq $command_url
    } keys %$buildings;

    next if !defined $command_id;

    my $command_type = Games::Lacuna::Client::Buildings::type_from_url($command_url);

    my $command = $client->building( id => $command_id, type => $command_type );
    my $plans   = $command->view_plans->{plans};

    next if !@$plans;

    printf "%s\n", $name;
    print "=" x length $name;
    print "\n\n";

    my $max_length = max map { length $_->{name} } @$plans;

    my %plan_count;

    for my $plan ( sort { $a->{name} cmp $b->{name} } @$plans ) {
        $plan_count{ $plan->{name} }{ $plan->{level} }{ $plan->{extra_build_level} } ++;
    }

    my %tags;
    for my $plan ( keys %plan_count ) {
        next if exists $tags{$plan};
        $tags{$plan} = [ get_tags( building_type_from_label($plan) ) ];
    }

    my @plans;
    for my $plan ( sort keys %plan_count ) {
        for my $level ( sort { $a <=> $b } keys %{ $plan_count{$plan} } ) {
            for my $extra ( sort { $a <=> $b } keys %{ $plan_count{$plan}{$level} } ) {
                my $type = building_type_from_label( $plan );

                push @plans, {
                    name  => $plan,
                    level => $level,
                    extra => $extra,
                    count => $plan_count{$plan}{$level}{$extra},
                    tags  => $tags{$plan},
                    type  => meta_type( $type ),
                };
            }
        }
    }

    report_plans_tag( \@plans, { tags => ['space_station_module'] } );
    report_plans_tag( \@plans, { type => 'glyph', tags => ['food', 'ore', 'water', 'energy', 'storage'], exclude => ['decoration'] } );
    report_plans_tag( \@plans, { type => 'glyph', exclude => ['decoration'] } );
    report_plans_tag( \@plans, { type => 'glyph' } );
    report_plans_tag( \@plans, { tags => ['food', 'ore', 'water', 'energy', 'storage'] } );
    report_plans_tag( \@plans );

    print "\n";
}

sub report_plans_tag {
    my ( $plans, $spec ) = @_;

    $spec ||= {};
    my @delete;

PLAN:
    for my $plan ( @$plans ) {

        if ( exists $spec->{type} ) {
            next PLAN
                if $spec->{type} ne $plan->{type};
        }

        if ( exists $spec->{tags} ) {
            my $match;

            for my $tag ( @{ $spec->{tags} } ) {
                if ( any { $tag eq $_ } @{ $plan->{tags} } ) {
                    $match = 1;
                    last;
                }
            }

            next PLAN
                if !$match;
        }

        if ( exists $spec->{exclude} ) {
            for my $tag ( @{ $spec->{exclude} } ) {
                next PLAN
                    if any { $tag eq $_ } @{ $plan->{tags} };
            }
        }

        printf "%s %d+%d",
            $plan->{name},
            $plan->{level},
            $plan->{extra};

        printf " (x%d)", $plan->{count}
            if $plan->{count} > 1;

        print "\n";

        push @delete, $plan;
    }

    print "\n" if @delete;

    # delete the ones we printed, so they don't get printed twice
    @$plans =
        grep {
            my $plan = $_;
            my $printed = any { refaddr($plan) == refaddr($_) } @delete;
            $printed ? () : $plan;
        } @$plans;

    return;
}
