#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

my $planet_name;

GetOptions(
    'planet=s' => \$planet_name,
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
	cfg_file => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if defined $planet_name && $planet_name ne $name;

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
    print "\n";
    
    my $max_length = max map { length $_->{name} } @$plans;
    
    my %plan;
    
    for my $plan ( sort { $a->{name} cmp $b->{name} } @$plans ) {
        $plan{ $plan->{name} }{ $plan->{level} }{ $plan->{extra_build_level} } ++;
    }
    
    for my $plan ( sort keys %plan ) {
        for my $level ( sort keys %{ $plan{$plan} } ) {
            for my $extra ( sort keys %{ $plan{$plan}{$level} } ) {
                printf "%s %d+%d",
                    $plan,
                    $level,
                    $extra;
                
                my $count = $plan{$plan}{$level}{$extra};
                
                printf " (x%d)", $count
                    if $count > 1;
                
                print "\n";
            }
        }
    }
    
    print "\n";
}
