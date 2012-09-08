package Games::Lacuna::Client::Buildings::Simple;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
use Class::MOP;

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
    Fissure
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

sub init {
  my $class = shift;
  foreach my $type (@BuildingTypes) {
    my $class_name = "Games::Lacuna::Client::Buildings::$type";
    Class::MOP::Class->create(
      $class_name => (
        superclasses => ['Games::Lacuna::Client::Buildings'],
      )
    );
  }
}

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
