#!/usr/bin/env perl
# For all your plan and glyph sifting needs
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));
use POSIX                 (qw(floor));
use DateTime;
use Date::Parse;
use Date::Format;
use JSON;
use utf8;

  my $random_bit = int rand 9999;
  my $data_dir = 'data';
  my $log_dir  = 'log';

  my %opts = (
    h            => 0,
    v            => 0,
    config       => "lacuna.yml",
    dump         => 0,
    outfile      => $log_dir . '/sift_shipped.js',
    min_plus     => 0,
    max_plus     => 30,
    min_base     => 1,
    max_base     => 30,
    fastest      => 1,
    sleep        => 1,
  );

  my $ok = GetOptions(\%opts,
    'config=s',
    'outfile=s',
    'v|verbose',
    'h|help',
    'dryrun',
    'from=s',
    'to=s',
    'dump',
    'sleep',

    'sname=s@',
    'stype=s@',
    'stay',
    'fastest',
    'largest' => sub { $opts{fastest} = 0 },
    'snum=i',

    'plan_match=s@',
    'p_num=i',
    'p_max=i',
    'p_leave=i',
    'min_plus=i',
    'max_plus=i',
    'min_base=i',
    'max_base=i',
    'p_city',
    'p_decor',
    'p_halls',
    'p_station',
    'p_standard',  # (Equiv of not city, station, glyph, or decor)
    'p_glyph',
    'p_all',
    
    'glyph_match=s@',
    'g_num=i',
    'g_max=i',
    'g_leave=i',
    'g_all',
  );

  unless ( $opts{config} and -e $opts{config} ) {
    $opts{config} = eval{
      require File::HomeDir;
      require File::Spec;
      my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
      File::Spec->catfile(
        $dist,
        'login.yml'
      ) if $dist;
    };
    unless ( $opts{config} and -e $opts{config} ) {
      die "Did not provide a config file";
    }
  }
  my $df;
  if ($opts{dump}) {
    open($df, ">", "$opts{outfile}") or die "Could not open $opts{outfile} for writing\n";
  }

  usage() if $opts{h} || !$opts{from} || !$opts{to} || !$ok;

  my $gorp;
  usage() unless ( $gorp = select_something(\%opts) );

  my $glc = Games::Lacuna::Client->new(
	cfg_file => $opts{config},
        rpc_sleep => $opts{sleep},
	 #debug    => 1,
  );

  my $json = JSON->new->utf8(1);

  my $empire  = $glc->empire->get_status->{empire};
  my $planets = $empire->{planets};

# reverse hash, to key by name instead of id
  my %planets_by_name = map { $planets->{$_}, $_ } keys %$planets;

  my $to_id = $planets_by_name{$opts{to}}
    or die "--to planet $opts{to} not found";

# Load planet data
  my $body      = $glc->body( id => $planets_by_name{ "$opts{from}" } );
  my $buildings = $body->get_buildings->{buildings};

# Find the TradeMin
  my $trade_min_id = first {
        $buildings->{$_}->{name} eq 'Trade Ministry'
  }
  grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
  keys %$buildings;

  my $trade_min = $glc->building( id => $trade_min_id,
                                     type => 'Trade' );

  my $plans_result  = $trade_min->get_plan_summary;
  my $glyphs_result = $trade_min->get_glyph_summary;
  my @plans         = @{ $plans_result->{plans} };
  my @glyphs        = @{ $glyphs_result->{glyphs} };
  my $pcargo_each   = $plans_result->{cargo_space_used_each};
  my $gcargo_each   = $glyphs_result->{cargo_space_used_each};

  if ( !@plans and !@glyphs) {
    print "No plans or glyphs available on $opts{from}\n";
    exit;
  }
  
  my $plan_types = return_ptypes();

  my $send_plans = [];
  my $send_glyphs = [];
# Will whittle down via match, type args, number of each, and max number
  if ($gorp eq "both" or $gorp eq "plan") {
    $send_plans = grab_plans(\@plans, $plan_types, \%opts);
  }

# Will whittle down via match, number of each, and max number
  if ($gorp eq "both" or $gorp eq "glyph") {
    $send_glyphs = grab_glyphs(\@glyphs, \%opts);
  }

# Get trade ships
# Trim by name and type
# Order by fast, largest
# Start sending.
  my @ships = @{$trade_min->get_trade_ships->{ships}};
  if ($opts{sname}) {
    my @tships;
    for my $ship (@ships) {
      push @tships, $ship if ( grep { $ship->{name} =~ /\Q$_\E/i } @{$opts{sname}});
    }
    @ships = @tships;
  }
  if ($opts{stype}) {
    my @tships;
    for my $ship (@ships) {
      push @tships, $ship if ( grep { $ship->{type} =~ /^\Q$_\E$/i } @{$opts{stype}});
    }
    @ships = @tships;
  }
  if ($opts{fastest}) {
    @ships = sort { $b->{speed} <=> $a->{speed} || $b->{hold_size} <=> $a->{hold_size} } @ships;
  }
  else {
    @ships = sort { $b->{hold_size} <=> $a->{hold_size} || $b->{speed} <=> $a->{speed} } @ships;
  }
  unless ( @ships ) {
    print "No ship matching \'";
    if ($opts{sname}) { print join(":", @{$opts{sname}}),":"; }
    if ($opts{stype}) { print join(":", @{$opts{stype}}); }
    print "\' found. Exiting\n";
    exit;
  }
  my $output;
  my $ships_used = 0;
  for my $ship (@ships) {
    my $ship_id = $ship->{id};
    my $ship_name = $ship->{name};
    my $sent_plans;
    my $sent_glyphs;
    ($sent_plans, $send_plans, $sent_glyphs, $send_glyphs) =
      send_ship($send_plans, $pcargo_each, $send_glyphs, $gcargo_each, $ship);
    if ($sent_plans or $sent_glyphs) {
      $output->{$ship_id} = {
        id => $ship_id,
        name => $ship_name,
        plans => $sent_plans,
        glyphs => $sent_glyphs,
      };
      $ships_used++;
      if ($opts{snum}) {
        last if ($ships_used >= $opts{snum});
      }
    }
    else {
      last;
    }
    last unless (scalar @{$send_plans} > 0 or scalar @{$send_glyphs} > 0);
  }

  if ($opts{dump}) {
    print $df $json->pretty->canonical->encode($output);
    close($df);
  }
  print "$glc->{total_calls} api calls made.\n";
  print "You have made $glc->{rpc_count} calls today\n";
exit;

sub pack_cargo {
  my ( $plans,  $pcargo_each, $pcargo_req,
       $glyphs, $gcargo_each, $gcargo_req,
       $hold_size) = @_;

  my $sent_plans;
  my $sent_glyphs;
  my $left_plans = [];
  my $left_glyphs = [];
  my $pnum = int($pcargo_req/$pcargo_each);
  my $gnum = int($gcargo_req/$gcargo_each);

  if ($pcargo_req > $hold_size) {
    my $fit = int($hold_size/$pcargo_each);
    if ($fit < $pnum) {
      ($sent_plans, $pnum, $left_plans) = max_num_of($plans, $fit);
      $pcargo_req = $pnum * $pcargo_each;
    }
  }
  else {
    $sent_plans = $plans;
  }

#
#  print "Now sending $pnum plans with $pcargo_req space needed.\n";
#
  if ($pcargo_req + $gcargo_req > $hold_size) {
    my $fit = int( ($hold_size - $pcargo_req)/$gcargo_each);
    if ($fit < $gnum) {
      ($sent_glyphs, $gnum, $left_glyphs) = max_num_of($glyphs, $fit);
      $gcargo_req = $gnum * $gcargo_each;
    }
  }
  else {
    $sent_glyphs = $glyphs;
  }
#
#  print "Now sending $gnum glyphs with $gcargo_req space needed.\n";
#  print "Total of ",$pcargo_req + $gcargo_req," needed for ";
#  my $quan;
#  for my $item (@{$sent_plans}, @{$sent_glyphs}) {
#    $quan += $item->{quantity};
#  }
#  print $quan, " items.\n";
#
  return ( $sent_plans, $left_plans, $sent_glyphs, $left_glyphs);
}

sub max_num_of {
  my ($items, $max) = @_;

  my @slice;
  my @remains;
  my $total = 0;
  for my $item (@{$items}) {
    if ( ( $total + $item->{quantity} ) >= $max) {
      my $rnum = $item->{quantity} - ($max - $total);
      my %remain = %{$item};
      $remain{quantity} = $rnum;
      push @remains , \%remain if $rnum > 0;
      $item->{quantity} = $max - $total;
      push @slice, $item if $item->{quantity} > 0;
      $total = $max;
    }
    else {
      $total += $item->{quantity};
      push @slice, $item;
    }
  }
  return (\@slice, $total, \@remains);
}

sub send_ship {
  my ($sent_plans, $pcargo_each, $sent_glyphs, $gcargo_each, $ship) = @_;

  return (0,0) unless (scalar $sent_plans > 0 or scalar $sent_glyphs > 0);
  my $left_plans; my $left_glyphs;

  my $ship_id;
  if ($ship) {
    my $pcargo_req = 0;
    my $gcargo_req = 0;
    for my $plan (@{$sent_plans}) {
      $pcargo_req += $plan->{quantity} * $pcargo_each;
    }
    for my $glyph (@{$sent_glyphs}) {
      $gcargo_req += $glyph->{quantity} * $gcargo_each;
    }
#
#    print "$pcargo_req plan space and $gcargo_req glyph space needed with $ship->{hold_size} hold size.\n";
#
    if ( $ship->{hold_size} < $pcargo_req + $gcargo_req ) {
      ( $sent_plans, $left_plans, $sent_glyphs, $left_glyphs) =
        pack_cargo( $sent_plans,  $pcargo_each, $pcargo_req,
                    $sent_glyphs, $gcargo_each, $gcargo_req,
                    $ship->{hold_size});
    }
    $ship_id = $ship->{id};
  }

  my @items;
  my $pship = 0;
  my $gship = 0;
  for my $plan (@{$sent_plans}) {
    push @items,
      {
        type              => 'plan',
        plan_type         => $plan->{plan_type},
        level             => $plan->{level},
        extra_build_level => $plan->{extra_build_level},
        quantity          => $plan->{quantity},
      }
      if ( $plan->{quantity} > 0 );
    $pship += $plan->{quantity};
  }
  for my $glyph (@{$sent_glyphs}) {
    push @items,
      {
        type     => 'glyph',
        name     => $glyph->{name},
        quantity => $glyph->{quantity},
      }
      if ( $glyph->{quantity} > 0 );
    $gship += $glyph->{quantity};
  }
  my $pleft = 0;
  for my $plan (@{$left_plans}) {
    $pleft += $plan->{quantity};
  }
  my $gleft = 0;
  for my $glyph (@{$left_glyphs}) {
    $gleft += $glyph->{quantity};
  }

  my $popt = set_options($ship_id, $opts{stay});
  my $return = "";
  if ( $opts{dryrun} ) {
    printf "Would have pushed %d plans and %d glyphs, leaving %d plans and %d glyphs using %s:%s\n",
           $pship, $gship, $pleft, $gleft, $ship->{type}, $ship->{id};
  }
  elsif ($pship + $gship == 0) {
    print "Nothing to ship!\n";
  }
  else {
    my $return = eval { $trade_min->push_items(
      $to_id,
      \@items,
      $popt ? $popt
             : ()
    )};
    if ($@) {
      print "$@ error!\n";
    }
    else {
      printf "Pushed %d plans and %d glyphs, leaving %d plans and %d glyphs using %s:%s.\n",
           $pship, $gship, $pleft, $gleft, $ship->{type}, $ship->{id};
      printf "Arriving %s\n", $return->{ship}{date_arrives};
    }
  }
  return ($sent_plans, $left_plans, $sent_glyphs, $left_glyphs);
}

exit;

sub set_options {
  my ($ship_id, $stay) = @_;

  my $popt;
  if ( $ship_id ) {
    $popt->{ship_id} = $ship_id;
  }
  if ( $stay ) {
    $popt->{stay} = 1;
  }
  if ($popt) {
    return $popt;
  }
  else {
    return 0;
  }
}

sub srt_items {
  my $aname = $a->{name};
  my $bname = $b->{name};
  $aname =~ s/ //g;
  $bname =~ s/ //g;
  if (defined $a->{level} and defined $a->{extra_build_level}) {
    my $aebl = ( $a->{extra_build_level} ) ? $a->{extra_build_level} : 0;
    my $bebl = ( $b->{extra_build_level} ) ? $b->{extra_build_level} : 0;
    $aname cmp $bname
      || $a->{level} <=> $b->{level}
      || $aebl <=> $bebl;
  }
  else {
    $aname cmp $bname;
  }
}

sub grab_glyphs {
  my ($glyphs, $opts) = @_;

  my @send_glyphs;
  my $total = 0;
  for my $glyph ( sort srt_items @{$glyphs} ) {
    unless ($opts->{g_all}) {
      if ($opts->{glyph_match}) {
        next unless ( grep { $glyph->{name} =~ /$_/i } @{$opts->{glyph_match}});
      }
    }
    if ($opts->{g_leave}) {
      if ($glyph->{quantity} > $opts->{g_leave}) {
        $glyph->{quantity} -= $opts->{g_leave};
      }
      else {
        $glyph->{quantity} = 0;
      }
    }
    if ($opts->{g_num}) {
      $glyph->{quantity} = $opts->{g_num} if ($opts->{g_num} < $glyph->{quantity});
    }
    if ($opts->{g_max}) {
      if ( ( $total + $glyph->{quantity} ) > $opts->{g_max}) {
        $glyph->{quantity} = $opts->{g_max} - $total;
      }
      else {
        $total += $glyph->{quantity};
      }
    }
    push @send_glyphs, $glyph if ($glyph->{quantity} > 0);
  }
  return \@send_glyphs;
}

sub grab_plans {
  my ($plans, $plan_types, $opts) = @_;
  
# If general types wanted, push them onto plan_match
  unless ($opts->{p_all}) {
    $opts->{plan_match} = build_match( $plan_types, $opts);
  }

#  my $json = JSON->new->utf8(1);
#  print $json->pretty->canonical->encode($opts);

# First grab all matched, min & max levels
  my @send_plans;
  my $total = 0;
  for my $plan ( sort srt_items @{$plans} ) {
    unless ($opts->{p_all}) {
      if ($opts->{plan_match}) {
        next unless ( grep { $plan->{name} =~ /$_/i } @{$opts->{plan_match}});
      }
    }
    if ($opts->{p_leave}) {
      if ($plan->{quantity} > $opts->{p_leave}) {
        $plan->{quantity} -= $opts->{p_leave};
      }
      else {
        $plan->{quantity} = 0;
      }
    }
#    print join(":",$plan->{name},$plan->{level}),"\n";
    if ($opts->{p_num}) {
#      print "Limiting to $opts->{p_num} from $plan->{quantity} to ";
      $plan->{quantity} = $opts->{p_num} if ($opts->{p_num} < $plan->{quantity});
#      print $plan->{quantity},"\n";
    }
    if ($opts->{p_max}) {
      if ( ( $total + $plan->{quantity} ) > $opts->{p_max}) {
        $plan->{quantity} = $opts->{p_max} - $total;
      }
      else {
        $total += $plan->{quantity};
      }
    }
    push @send_plans, $plan
      if ( $plan->{quantity} > 0 and
               $plan->{level} >= $opts->{min_base} and
               $plan->{level} <= $opts->{max_base} and
               $plan->{extra_build_level} >= $opts->{min_plus} and
               $plan->{extra_build_level} <= $opts->{max_plus});
  }
  return \@send_plans;
}

sub build_match {
  my ($plan_types, $opts ) = @_;

  my @matches;
  if ($opts->{plan_match}) {
    push @matches, @{$opts->{plan_match}};
  }
  if ($opts->{p_city}) {
    push @matches, @{$plan_types->{city}};
  }
  if ($opts->{p_decor}) {
    push @matches, @{$plan_types->{decor}};
  }
  if ($opts->{p_halls}) {
    push @matches, @{$plan_types->{halls}};
  }
  if ($opts->{p_glyph}) {
    push @matches, @{$plan_types->{glyph}};
  }
  if ($opts->{p_station}) {
    push @matches, @{$plan_types->{station}};
  }
  if ($opts->{p_standard}) {
    push @matches, @{$plan_types->{standard}};
  }
  my %seen =() ;
  my @unique_match = grep { ! $seen{$_}++ } @matches;

  return \@unique_match;
}

sub return_ptypes {

  my %plan_types;

# Lost City (A) - (I)
  $plan_types{city} = [
    "Lost City of Tyleon",
   ];

# Beach [1] - [13]
  $plan_types{decor} = [
    "Beach",
    "Crater",
    "Grove of Trees",
    "Lagoon",
    "Lake",
    "Patch of Sand",
    "Rocky Outcropping",
   ];

  $plan_types{any} = [
    "Black Hole Generator",
    "Citadel of Knope",
    "Crashed Ship Site",
    "Gas Giant Settlement Platform",
    "Interdimensional Rift",
    "Junk Henge Sculpture",
    "Kalavian Ruins",
    "Library of Jith",
    "Metal Junk Arches",
    "Great Ball of Junk",
    "Oracle of Anid",
    "Pantheon of Hagness",
    "Pyramid Junk Sculpture",
    "Space Junk Park",
    "Subspace Supply Depot",
    "Temple of the Drajilites"
   ];

  $plan_types{plus} = [
    "Interdimensional Rift",
    "Kalavian Ruins",
    "Pantheon of Hagness",
  ];

  $plan_types{halls} = [
    "Halls of Vrbansk",
  ];

  $plan_types{glyph} = [
    "Algae Pond",
    "Amalgus Meadow",
    "Beeldeban Nest",
    "Black Hole Generator",
    "Citadel of Knope",
    "Crashed Ship Site",
    "Denton Brambles",
    "Gas Giant Settlement Platform",
    "Geo Thermal Vent",
    "Great Ball of Junk",
    "Interdimensional Rift",
    "Junk Henge Sculpture",
    "Kalavian Ruins",
    "Lapis Forest",
    "Library of Jith",
    "Malcud Field",
    "Metal Junk Arches",
    "Natural Spring",
    "Oracle of Anid",
    "Pantheon of Hagness",
    "Pyramid Junk Sculpture",
    "Ravine",
    "Space Junk Park",
    "Temple of the Drajilites",
    "Volcano",
   ];
  $plan_types{station} = [
    "Art Museum",
    "Culinary Institute",
    "Interstellar Broadcast System",
    "Opera House",
    "Parliament",
    "Police Station",
    "Station Command Center",
    "Warehouse",
   ];
  $plan_types{standard} = [
    "Algae Cropper",
    "Algae Syrup Bottler",
    "Amalgus Bean Soup Cannery",
    "Apple Cider Bottler",
    "Archaeology Ministry",
    "Atmospheric Evaporator",
    "Beeldeban Protein Shake Factory",
    "Bread Bakery",
    "Cheese Maker",
    "Cloaking Lab",
    "Corn Meal Grinder",
    "Denton Root Chip Frier",
    "Denton Root Patch",
    "Deployed Bleeder",
    "Embassy",
    "Energy Reserve",
    "Espionage Ministry",
    "Fusion Reactor",
    "Genetics Lab",
    "Intelligence Ministry",
    "Lapis Orchard",
    "Lapis Pie Bakery",
    "Luxury Housing",
    "Malcud Burger Packer",
    "Malcud Fungus Farm",
    "Mercenaries Guild",
    "Mine",
    "Munitions Lab",
    "Network 19 Affiliate",
    "Observatory",
    "Ore Refinery",
    "Ore Storage Tanks",
    "Planetary Command Center",
    "Potato Pancake Factory",
    "Security Ministry",
    "Shield Against Weapons",
    "Shipyard",
    "Singularity Energy Plant",
    "Space Port",
    "Station Command Center",
    "Supply Pod",
    "Trade Ministry",
    "Waste Digester",
    "Waste Sequestration Well",
    "Water Reclamation Facility",
    "Water Storage Tank",
   ];

  return \%plan_types;
}

sub select_something {
  my ($opts) = @_;

  my @pselect = qw(
    plan_match
    p_all
    p_city
    p_decor
    p_glyph
    p_halls
    p_standard
    p_station
  );

  my @gselect = qw(
    glyph_match
    g_all
    g_max
    g_num
  );

  my $gsel = 0;
  my $psel = 0;
  for my $key (keys %$opts) {
    $psel = 1 if ( $opts->{$key} and (grep { $_ eq $key } @pselect));
    $gsel = 1 if ( $opts->{$key} and (grep { $_ eq $key } @gselect));
  }
  if ($gsel and $psel) {
    return "both";
  }
  elsif ($gsel) {
    return "glyph";
  }
  elsif ($psel) {
    return "plan";
  }
  print STDERR "You must make some sort of selection criteria for glyphs and plans.\n";
  return 0;
}

sub usage {
  die <<END_USAGE;
Usage: $0 --to PLANET --from PLANET
       --config      Config File
       --outfile     Dumpfile of data
       --dump        Dump data
       --verbose     More info output
       --help        This message
       --dryrun      Dryrun
       --from        PLANET_NAME    (REQUIRED)
       --to          PLANET_NAME    (REQUIRED)

Ship Options
       --sname       SHIP NAME REGEX
       --stype       SHIP TYPE Exact_Match
       --stay        Have tradeship stay
       --fastest     Grab fastest ships first (default)
       --largest     Grab largest ships first
       --snum        Use up to this number of ships

Plan Options
       --plan_match  PLAN NAME REGEX (Can be multiple options)
       --p_num       Maximum number of each plan to push
       --p_max       Maximum number of plans to push
       --min_plus    Minimum Plus to plans to move (only base 1 plans looked at)
       --max_plus    Maximum Plus to plans to move (only base 1 plans looked at)
       --min_base    Minimum Base for plans to move
       --max_base    Maximum Base for plans to move
       --p_all       Grab All plans
       --p_decor     Grab Decor plans
       --p_glyph     Grab Glyph Plans (that are not decor or Halls) Note, they don't use a plot.
       --p_hall      Grab Hall Plans
       --p_standard  Grab all "standard" building plans
       --p_station   Grab Space Station Plans
       --p_leave     Leave this number of each plan behind

Glyph Options
       --glyph_match GLYPH NAME REGEX (Can be put in multiple times)
       --g_all       Grab all plans
       --g_num       Maximum number of each glyph to push
       --g_max       Maximum number of glyphs to push
       --g_leave     Leave this number of each type of glyph behind

Pushes plans and glyphs between your own planets.

Examples:
  Send all 1+4 glyph plans     : $0 --to Planet --from Planet --p_glyph --max_base 1 --min_plus 4
  Send 10 gold & bauxite glyphs: $0 --to Planet --from Planet --glyph_match gold --glyph bauxite --g_num 10
  Send all plans & glyphs      : $0 --to Planet --from Planet --p_all --g_all
END_USAGE

}

