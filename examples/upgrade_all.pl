#!/usr/bin/env perl
#
# Add ability to define which planets not to do

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

  our %opts = (
        h => 0,
        v => 0,
        maxlevel => 30,
        maxnum => 31,
        config => "lacuna.yml",
        dumpfile => "log/all_builds.js",
        maxadd  => 31,
        wait    => 8 * 60 * 60,
        sleep  => 1,
        extra  => [],
        noup   => [],
        id     => [],
  );

  my $ok = GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'planet=s@',
    'skip=s@',
    'config=s',
    'dumpfile=s',
    'unhappy',
    'id=i@',
    'maxadd=i',
    'maxlevel=i',
    'maxnum=i',
    'dry',
    'wait=i',
    'junk',
    'glyph',
    'space',
    'city',
    'lab',
    'module',
    'nostandard',
    'match=s@',
    'noup=s@',
    'extra=s@',
    'sleep=i',
    'noloop',
  );

  my $bld_names = set_items();
  usage($bld_names) if (!$ok or $opts{h});
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  open(OUTPUT, ">", $opts{dumpfile}) || die "Could not open $opts{dumpfile} for writing";

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  print "Starting RPC: $glc->{rpc_count}\n";

# If ids are specified, then we will upgrade regardless of type options
  if (scalar @{$opts{id}} > 0) {
    $opts{junk} = $opts{glyph} = $opts{space} = $opts{city} = $opts{lab} = $opts{module} = 1;
  }
# Get planets
  my %planets;
  if ($opts{module}) {
    %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
    $status->{planets} = \%planets;
  }
  else {
    %planets = map { $empire->{colonies}{$_}, $_ } keys %{$empire->{colonies}};
    $status->{planets} = \%planets;
  }

  my @plist = planet_list(\%planets, \%opts);

  my $keep_going = 1;
  my $lowestqueuetimer = $opts{wait} - 1;
  my $currentqueuetimer = 0;
  my %build_err;
  do {
    my $pname;
    my @skip_planets;
    for $pname (sort keys %planets) {
      unless (grep { $pname eq $_ } @plist) {
        push @skip_planets, $pname;
        next;
      }
      print "Inspecting $pname\n";
      my $planet    = $glc->body(id => $planets{$pname});
      my $result    = $planet->get_buildings;
      my $buildings = $result->{buildings};
      my $station = $result->{status}{body}{type} eq 'space station' ? 1 : 0;
      my $happiness = $result->{status}{body}{happiness};
      if ($happiness < 0 and !$opts{unhappy}) {
        print "$pname is unhappy and is being skipped\n";
        push @skip_planets, $pname;
        next;
      }
      if ($station and not $opts{module}) {
        push @skip_planets, $pname;
        next;
      }
# Station and checking for resources needed.
      my ($sarr, $pending) = bstats($buildings, \%build_err, $station);
      if ($pending > 0) {
        $currentqueuetimer = $pending;
      }
      elsif (scalar @$sarr == 0) {
        print "No buildings to upgrade on $pname\n";
        $currentqueuetimer = $opts{wait} + 1;
      }
      for my $bld (@$sarr) {
        my $ok;
        my $bldstat = "Bad";
        my $reply = "";
        $ok = eval {
          my $type = get_type_from_url($bld->{url});
          my $bldpnt = $glc->building( id => $bld->{id}, type => $type);
          if ($opts{dry}) {
            $reply = "dry run";
            $lowestqueuetimer = $opts{wait} - 1;
          }
          else {
            $reply = "upgrading";
            $bldstat = $bldpnt->upgrade();
            $currentqueuetimer = $bldstat->{building}->{pending_build}->{seconds_remaining};
          }
        };
        printf "%7d %10s l:%2d x:%2d y:%2d %s\n",
                 $bld->{id}, $bld->{name},
                 $bld->{level}, $bld->{x}, $bld->{y}, $reply;
        unless ($ok) {
          print "$@ Error; Placing building on skip list\n";
          $build_err{$bld->{id}} = $@;
        }
      }
      if ($lowestqueuetimer > $currentqueuetimer ) {
        $lowestqueuetimer = $currentqueuetimer;
        printf sec2str($lowestqueuetimer);
        printf " new lowest sleep time.\n";
      }  
      $status->{"$pname"} = $sarr;
      if ($currentqueuetimer > $opts{wait}) {
        print "Queue of ", sec2str($currentqueuetimer),
              " is longer than wait period of ",sec2str($opts{wait}), ", taking $pname off of list.\n";
        push @skip_planets, $pname;
      }
    }
    print "Done or skipping: ",join(":", sort @skip_planets), "\n";
    for $pname (@skip_planets) {
      delete $planets{$pname};
    }
    if ($opts{noloop}) {
      $keep_going = 0;
    }
    elsif (keys %planets) {
      print "Clearing Queue for ",sec2str($lowestqueuetimer),".\n";
      sleep $lowestqueuetimer if $lowestqueuetimer > 0;
      $lowestqueuetimer = $opts{wait} - 1;
    }
    else {
      print "Nothing Else to do.\n";
      $keep_going = 0;
    }
  } while ($keep_going);

 print OUTPUT $json->pretty->canonical->encode($status);
 close(OUTPUT);
 print "Ending   RPC: $glc->{rpc_count}\n";

exit;

sub planet_list {
  my ($phash, $opts) = @_;

  my @good_planets;
  for my $pname (sort keys %$phash) {
    if ($opts->{skip}) {
      next if (grep { $pname eq $_ } @{$opts->{skip}});
    }
    if ($opts->{planet}) {
      push @good_planets, $pname if (grep { $pname eq $_ } @{$opts->{planet}});
    }
    else {
      push @good_planets, $pname;
    }
  }
  return @good_planets;
}

sub set_items {
  my @bld_names;
  my $unless = [
  "Beach [1]",
  "Beach [10]",
  "Beach [11]",
  "Beach [12]",
  "Beach [13]",
  "Beach [2]",
  "Beach [3]",
  "Beach [4]",
  "Beach [5]",
  "Beach [6]",
  "Beach [7]",
  "Beach [8]",
  "Beach [9]",
  "Crater",
  "Essentia Vein",
  "Fissure",
  "Gas Giant Settlement Platform",
  "Grove of Trees",
  "Lagoon",
  "Lake",
  "Rocky Outcropping",
  "Patch of Sand",
  "Supply Pod",
  "Terraforming Platform",
  ];
  my $junk = [
    "Great Ball of Junk",
    "Junk Henge Sculpture",
    "Metal Junk Arches",
    "Pyramid Junk Sculpture",
    "Space Junk Park",
  ];
  my $glyph = [
  "Algae Pond",
  "Amalgus Meadow",
  "Beeldeban Nest",
  "Black Hole Generator",
  "Citadel of Knope",
  "Crashed Ship Site",
  "Denton Brambles",
  "Geo Thermal Vent",
  "Gratch's Gauntlet",
  "Interdimensional Rift",
  "Kalavian Ruins",
  "Kastern's Keep",
  "Lapis Forest",
  "Library of Jith",
  "Malcud Field",
  "Massad's Henge",
  "Natural Spring",
  "Oracle of Anid",
  "Pantheon of Hagness",
  "Ravine",
  "Temple of the Drajilites",
  "Volcano",
  ];
  my $space = [
    "Space Port",
  ];
  my $city = [
    "Lost City of Tyleon (A)",
    "Lost City of Tyleon (B)",
    "Lost City of Tyleon (C)",
    "Lost City of Tyleon (D)",
    "Lost City of Tyleon (E)",
    "Lost City of Tyleon (F)",
    "Lost City of Tyleon (G)",
    "Lost City of Tyleon (H)",
    "Lost City of Tyleon (I)",
  ];
  my $lab = [
    "Space Station Lab (A)",
    "Space Station Lab (B)",
    "Space Station Lab (C)",
    "Space Station Lab (D)",
    "Gas Giant Lab",
    "Terraforming Lab",
  ];
  my $module = [
    "Art Museum",
    "Culinary Institute",
    "Interstellar Broadcast System",
    "Opera House",
    "Parliament",
    "Police Station",
    "Station Command Center",
    "Warehouse",
  ];
  my $standard = [
    "Algae Cropper",
    "Apple Orchard",
    "Archaeology Ministry",
    "Atmospheric Evaporator",
    "Amalgus Bean Plantation",
    "Beeldeban Herder",
    "Bread Bakery",
    "Malcud Burger Packer",
    "Capitol",
    "Cheese Maker",
    "Denton Root Chip Frier",
    "Apple Cider Bottler",
    "Cloaking Lab",
    "Corn Plantation",
    "Corn Meal Grinder",
    "Dairy Farm",
    "Denton Root Patch",
    "Development Ministry",
    "Distribution Center",
    "Embassy",
    "Energy Reserve",
    "Entertainment District",
    "Espionage Ministry",
    "Fission Reactor",
    "Food Reserve",
    "Fusion Reactor",
    "Genetics Lab",
    "Geo Energy Plant",
    "Hydrocarbon Energy Plant",
    "Intel Training",
    "Intelligence Ministry",
    "Lapis Orchard",
    "Luxury Housing",
    "Malcud Fungus Farm",
    "Mayhem Training",
    "Mercenaries Guild",
    "Mine",
    "Mining Ministry",
    "Mission Command",
    "Munitions Lab",
    "Network 19 Affiliate",
    "Observatory",
    "Ore Refinery",
    "Ore Storage Tanks",
    "Oversight Ministry",
    "Park",
    "Lapis Pie Bakery",
    "Pilot Training Facility",
    "Planetary Command Center",
    "Politics Training",
    "Potato Pancake Factory",
    "Potato Patch",
    "Propulsion System Factory",
    "Shield Against Weapons",
    "Security Ministry",
    "Beeldeban Protein Shake Factory",
    "Shipyard",
    "Singularity Energy Plant",
    "Amalgus Bean Soup Cannery",
    "Stockpile",
    "Subspace Supply Depot",
    "Algae Syrup Bottler",
    "Theft Training",
    "Theme Park",
    "Trade Ministry",
    "Subspace Transporter",
    "University",
    "Waste Digester",
    "Waste Energy Plant",
    "Waste Exchanger",
    "Waste Recycling Center",
    "Waste Sequestration Well",
    "Waste Treatment Center",
    "Water Production Plant",
    "Water Purification Plant",
    "Water Reclamation Facility",
    "Water Storage Tank",
    "Wheat Farm",
  ];
  if ($opts{nostandard}) {
    push @{$opts{noup}}, @$standard;
  }
  if ($opts{junk}) {
    push @{$opts{extra}}, @$junk;
  }
  else {
    push @{$opts{noup}}, @$junk;
  }
  if ($opts{glyph}) {
    push @{$opts{extra}}, @$glyph;
  }
  else {
    push @{$opts{noup}}, @$glyph;
  }
  if ($opts{space}) {
    push @{$opts{extra}}, @$space;
  }
  else {
    push @{$opts{noup}}, @$space;
  }
  if ($opts{city}) {
    push @{$opts{extra}}, @$city;
  }
  else {
    push @{$opts{noup}}, @$city;
  }
  if ($opts{lab}) {
    push @{$opts{extra}}, @$lab;
  }
  else {
    push @{$opts{noup}}, @$lab;
  }
  if ($opts{module}) {
    push @{$opts{extra}}, @$module;
  }
  else {
    push @{$opts{noup}}, @$module;
  }
  push @{$opts{noup}}, @$unless;

  push @bld_names, sort @$unless, @$junk, @$glyph, @$space, @$city, @$lab,
                         @$module, @$standard;
  return \@bld_names;
}

sub bstats {
  my ($bhash, $berr, $station) = @_;

  my $bcnt = 0;
  my $dlevel = $station ? 121 : 0;
  my @sarr;
  my $pending = 0;
  for my $bid (keys %$bhash) {
    if ($bhash->{$bid}->{name} eq "Development Ministry") {
      $dlevel = $bhash->{$bid}->{level};
    }
    $dlevel = $opts{maxnum} if ( $opts{maxnum} < $dlevel );
    if ( defined($bhash->{$bid}->{pending_build})) {
      $bcnt++;
      $pending = $bhash->{$bid}->{pending_build}->{seconds_remaining}
          if ($bhash->{$bid}->{pending_build}->{seconds_remaining} > $pending);
    }
    else {
      next unless (scalar @{$opts{id}} == 0 or grep { $bid eq $_ } @{$opts{id}});
      my $doit = check_type($bhash->{$bid});
      $doit = 0 if ($berr->{$bid});
      if ($doit) {
#        print "Doing $bhash->{$bid}->{name}\n";
        my $ref = $bhash->{$bid};
        $ref->{id} = $bid;
        push @sarr, $ref if ($ref->{level} < $opts{maxlevel} && $ref->{efficiency} == 100);
      }
      else {
#        print "Skip  $bhash->{$bid}->{name}\n";
      }
    }
  }
  @sarr = sort { $a->{level} <=> $b->{level} ||
                 $a->{x} <=> $b->{x} ||
                 $a->{y} <=> $b->{y} } @sarr;
  if (scalar @sarr > ($dlevel + 1 - $bcnt)) {
    splice @sarr, ($dlevel + 1 - $bcnt);
  }
  if (scalar @sarr > $opts{maxadd}) {
    splice @sarr, $opts{maxadd};
  }
  return (\@sarr, $pending);
}

sub check_type {
  my ($bld) = @_;
  
  print "Checking $bld->{name} - " if ($opts{v});
  if ($opts{match}) {
    if (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{match}}) {
      print "Match\n" if ($opts{v});
      return 1;
    }
    else {
      print "No match\n" if ($opts{v});
      return 0;
    }
  }
  if ($opts{extra} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{extra}})) {
    print "Extra\n" if ($opts{v});
    return 1;
  }
  if ($opts{noup} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{noup}})) {
    print "Skipping\n" if ($opts{v});
    return 0;
  }
  print "Default\n" if ($opts{v});
  return 1;
}

sub sec2str {
  my ($sec) = @_;

  my $day = int($sec/(24 * 60 * 60));
  $sec -= $day * 24 * 60 * 60;
  my $hrs = int( $sec/(60*60));
  $sec -= $hrs * 60 * 60;
  my $min = int( $sec/60);
  $sec -= $min * 60;
  return sprintf "%04d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
}

sub get_type_from_url {
  my ($url) = @_;

  my $type;
  eval {
    $type = Games::Lacuna::Client::Buildings::type_from_url($url);
  };
  if ($@) {
    print "Failed to get building type from URL '$url': $@";
    return 0;
  }
  return 0 if not defined $type;
  return $type;
}

sub usage {
    my ($bld_names) = @_;
    diag(<<END);
Usage: $0 [options]

This program upgrades planets on your planet. Faster than clicking each port.
It will upgrade in order of level up to maxlevel.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config FILE      - Specify a GLC config file, normally lacuna.yml
  --planet NAME      - Specify planet, multiple done by --planet P1 --planet P2
  --skip  PLANET     - Do not process this planet. Multiple as planet
  --dumpfile FILE    - data dump for all the info we don't print
  --maxlevel INT     - do not upgrade if this level has been achieved
  --maxnum INT       - Use this if lower than dev ministry level
  --maxadd INT       - Add at most INT buildings to the queue per pass
  --id INT           - Upgrade specific building id. Multiple as planet
  --wait   INT       - Max number of seconds to wait to repeat loop
  --sleep  INT       - Pause between RPC calls. Default 1
  --junk             - Upgrade Junk Buildings
  --glyph            - Upgrade Glyph Buildings
  --space            - Upgrade spaceports
  --city             - Upgrade LCOT
  --lab              - Upgrade labs
  --noloop           - Do not try to loop, just quit after upgrading
  --nostandard       - Do not upgrade anything that is not in the other catagories
  --match STRING     - Only upgrade matching building names
  --noup  STRING     - Skip building names (multiple allowed)
  --extra STRING     - Add matching names to usual list to upgrade
  --unhappy          - Skip planets that are unhappy unless this flag is set
  --dry              - Do not actually upgrade
END
  print "\nBuilding Names: ",join(", ", sort @$bld_names ),"\n";
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}
