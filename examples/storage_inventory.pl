#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Number::Format qw( format_number );
use List::Util qw( max );
use Games::Lacuna::Client ();
use Getopt::Long qw(GetOptions);
use File::Basename;


##----------------------------------------------------------------------
##----------------------------------------------------------------------
## no critic (RequireArgUnpacking)
sub accumlate_hash
{
  my $lh_hash_ref  = shift;
  my @rh_hash_refs = @_;

  foreach my $rh_hash_ref (@rh_hash_refs)
  {
    while (my ($key, $value) = each(%{$rh_hash_ref}))
    {
      if (is_number($value))
      {
        if (!exists($lh_hash_ref->{$key}))
        {
          $lh_hash_ref->{$key} = $value;
        }
        else
        {
          $lh_hash_ref->{$key} += $value;
        }
      }
    }
  }
  return;
}
## use critic
##----------------------------------------------------------------------
##----------------------------------------------------------------------
sub is_number
{
  my $value = shift;
  if (defined($value))
  {
    return ((ref($value) eq qq{}) && ($value =~ /^\d+$/x));
  }
  return;
}

##----------------------------------------------------------------------
##----------------------------------------------------------------------
sub print_hash
{
  my $hash_ref = shift;

  my $column = 0;

  foreach my $key (sort(keys(%{$hash_ref})))
  {
    printf("  %12s %10s",
      $key, (is_number($hash_ref->{$key}) ? $hash_ref->{$key} : qq{-}));
    if (++$column >= 3)
    {
      print qq{\n};
      $column = 0;
    }
  }
  if ($column)
  {
    print qq{\n};
  }
  return;
}

##----------------------------------------------------------------------
##----------------------------------------------------------------------
sub show_usage
{
  my $script = basename($0);

  print << "_END_USAGE_";
Usage:  perl $script {--food} {--ore} {--planet="Planet Name"} account_file

This script will show the inventory of each planet in the user's Empire.

Valid options:
  --food                  Show only Food Reservers
  --ore                   Show only Ore Storage
  --planet="PLANET NAME"  Show information for specified planet
  account_file            Configuration file DEFAULT: lacuna.yml

_END_USAGE_

  return;
}
##----------------------------------------------------------------------
## MAIN script body
##----------------------------------------------------------------------
my $show_usage;
my $target_planet;
my $show_ore;
my $show_food;
my $debug_level = 0;
my $cfg_file;

## Pass through unknown parameters in @ARGV
Getopt::Long::Configure(qw(pass_through ));

GetOptions(
    'help'      => \$show_usage,
    'food!'     => \$show_food,
    'ore!'      => \$show_ore,
    'planet=s'  => \$target_planet,
    'debug+'    => \$debug_level,
    'config=s'  => \$cfg_file,
);

if ($show_usage)
{
  show_usage();
  exit(0);
}

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

if (!$cfg_file)
{
  $cfg_file = shift(@ARGV) || 'lacuna.yml';
}

if (! -e $cfg_file)
{
  die(qq{Could not find the config file "$cfg_file"\n});
}

## See if there are any unknown args
if (scalar(@ARGV))
{
  print qq{ERROR: Unknown argument(s): "}, join(qq{", "}, @ARGV), qq{"\n\n};
  show_usage();
  exit(1);
}

## Create the Client object
my $client = Games::Lacuna::Client->new(
  cfg_file => $cfg_file,
  debug    => ($debug_level ? 1 : 0),
);

## List for types of resources to check
my @types = ();

## See if user specified food
if ($show_food)
{
  push(@types, qq{food});
}

## See if user specified ore
if ($show_ore)
{
  push(@types, qq{ore});
}

## Default to both, if neither is given
if (scalar(@types) == 0)
{
  @types = qw(food ore);
}


# Load the planets
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

## Hash to hold storage by planet
my $stores = {};

## Scan each planet
PLANET_LOOP:
foreach my $planet_id (sort keys %$planets)
{
  my $planet_name = $planets->{$planet_id};

  ## If we are looking for only one planet
  if ($target_planet && (uc($planet_name) ne uc($target_planet)))
  {
    ## This isn't the planet, next
    next PLANET_LOOP;
  }

  ## Load planet data
  my $planet    = $client->body(id => $planet_id);
  my $result    = $planet->get_buildings;
  ## Extract body from the results
  my $body      = $result->{status}->{body};
  ## Create reference for easier to read code
  my $buildings = $result->{buildings};

  ## List for resource storage buildings found on planet
  my @storage_buildings = ();

  ## Iterate through the types
  for my $type (@types)
  {
    ## initialize hash
    $stores->{$planet_name}->{$type} = {};

    ## Determine name of building, based on resource type
    my $building = {
      food => 'Food Reserve',
      ore  => 'Ore Storage Tanks',
    }->{$type};

    ## Iterate through buildings
    while (my ($building_id, $building_ref) = each(%{$buildings}))
    {
      ## See if it is what we are looking for
      if ($building_ref->{name} eq $building)
      {
        ## Store it in the list
        push(
          @storage_buildings,
          {
            id   => $building_id,
            type => $type,
            building_type =>
              {food => qq{FoodReserve}, ore => qq{OreStorage}}->{$type},
          }
        );
      }
    }
  }

  ## Iterate through the list of storage buildings
  foreach my $info_ref (@storage_buildings)
  {
    ## Get the view info, which has the food_stored or ore_stored key
    my $view = $client->building(
      id   => $info_ref->{id},
      type => $info_ref->{building_type}
    )->view;

    ## Set the key by adding _stored to the type
    my $key = $info_ref->{type} . qq{_stored};
    ## Accumulate the totals into the planet hash
    accumlate_hash($stores->{$planet_name}->{$info_ref->{type}}, $view->{$key});
  }
}

## Hash for the empire totals
my $empire_stores = {food => {}, ore => {}};

## Iterate through the planet stores
foreach my $planet_name (sort(keys(%{$stores})))
{
  print "$planet_name\n";
  print "=" x length $planet_name;
  print "\n";

  ## Iterate through the resource types
  foreach my $type (@types)
  {
    print qq{$type\n}, qq{-} x length($type), qq{\n};
    print_hash($stores->{$planet_name}->{$type});
    accumlate_hash($empire_stores->{$type}, $stores->{$planet_name}->{$type});
    print qq{\n};
  }

}

## Display the empire wide totals
if (!$target_planet)
{
  print qq{Empire Totals\n=============\n};
  foreach my $type (@types)
  {
    print qq{$type\n}, qq{-} x length($type), qq{\n};
    print_hash($empire_stores->{$type});
    print qq{\n};
  }
}


