package Games::Lacuna::Client::Buildings::Simple;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;

use namespace::clean;
use Moose;

extends 'Games::Lacuna::Client::Module';

our @BuildingTypes = (qw(
    Algae
    AlgaePond
    AmalgusMeadow
    Apple
    AtmosphericEvaporator
    Beach1
    Beach2
    Beach3
    Beach4
    Beach5
    Beach6
    Beach7
    Beach8
    Beach9
    Beach10
    Beach11
    Beach12
    Beach13
    Bean
    Beeldeban
    BeeldebanNest
    Bread
    Burger
    Cheese
    Chip
    Cider
    CitadelOfKnope
    CloakingLab
    Corn
    CornMeal
    CrashedShipSite
    Crater
    Dairy
    Denton
    DentonBrambles
    DeployedBleeder
    Espionage
    EssentiaVein
    Fission
    Fusion
    GasGiantLab
    GasGiantPlatform
    Geo
    GeoThermalVent
    GratchsGauntlet
    GreatBallOfJunk
    Grove
    HydroCarbon
    InterDimensionalRift
    JunkHengeSculpture
    KalavianRuins
    KasternsKeep
    Lagoon
    Lake
    Lapis
    LapisForest
    LCOTA
    LCOTB
    LCOTC
    LCOTD
    LCOTE
    LCOTF
    LCOTG
    LCOTH
    LCOTI
    LuxuryHousing
    Malcud
    MalcudField
    MassadsHenge
    MetalJunkArches
    Mine
    MunitionsLab
    NaturalSpring
    OreRefinery
    Oversight
    Pancake
    PantheonOfHagness
    Pie
    PilotTraining
    Potato
    Propulsion
    PyramidJunkSculpture
    Ravine
    RockyOutcrop
    Sand
    SAW
    Shake
    Singularity
    Soup
    SpaceJunkPark
    SSLB
    SSLC
    SSLD
    Stockpile
    SupplyPod
    Syrup
    TerraformingLab
    TerraformingPlatform
    TheDillonForge
    University
    Volcano
    WasteDigester
    WasteEnergy
    WasteSequestration
    WasteTreatment
    WaterProduction
    WaterPurification
    WaterReclamation
    Wheat
  ),
);


#  WasteDigester => url is 'wastetreatment' according to docs, but I don't believe it!

{
  my $class = shift;
  my $simple_file = $INC{'Games/Lacuna/Client/Buildings/Simple.pm'};
  foreach my $type (@BuildingTypes) {
    my $class_name = "Games::Lacuna::Client::Buildings::$type";
    Moose::Meta::Class->create(
      $class_name => (
        superclasses => ['Games::Lacuna::Client::Buildings'],
      )
    );

    # this prevents "require" from trying to load the module
    my $inc_name = $class_name.'.pm';
    $inc_name =~ s(::){/}g;
    $INC{$inc_name} = $simple_file;
  }
}


has building_id => (
  is => 'ro',
  isa => 'Int',
  init_arg => 'id',
);

sub api_methods {
  return {
    build               => { default_args => [qw(session_id)] },
    view                => { default_args => [qw(session_id building_id)] },
    upgrade             => { default_args => [qw(session_id building_id)] },
    demolish            => { default_args => [qw(session_id building_id)] },
    downgrade           => { default_args => [qw(session_id building_id)] },
    get_stats_for_level => { default_args => [qw(session_id building_id)] },
    repair              => { default_args => [qw(session_id building_id)] },
  };
}

sub build {
  my $self = shift;
  # assign id for this object after building
  my $rv = $self->_build(@_);
  $self->{building_id} = $rv->{building}{id};
  return $rv;
}

{
  my %type_for;

  sub type_for {
    my ($class, $hint) = @_;

    if (! keys %type_for) { # initialise mapping if needed
      %type_for = map { lc($_) => $_ }
        @Games::Lacuna::Client::Buildings::BuildingTypes,
        @Games::Lacuna::Client::Buildings::Simple::BuildingTypes;
    }

    $hint =~ s{.*/}{}mxs;
    $hint = lc($hint);
    return $type_for{$hint} || undef;
  }
}

sub type_from_url {
  my $url = shift;
  croak "URL is undefined" if not $url;
  $url =~ m{/([^/]+)$} or croak("Bad URL: '$url'");
  my $url_elem = $1;
  my $type = type_for(__PACKAGE__, $url) or croak("Bad URL: '$url'");
  return $type;
}

sub subclass_for {
  my ($class, $type) = @_;
  $type = $class->type_for($type);
  return "Games::Lacuna::Client::Buildings::$type";
}

no Moose;
__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Simple - All the simple buildings

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
