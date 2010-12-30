package Games::Lacuna::Client::PrettyPrint;
use English qw(-no_match_vars);
use List::Util qw(sum);
use warnings;
no warnings 'uninitialized';
use Term::ANSIColor;

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT_OK = qw(trace message warning action ptime phours);
our $ansi_color = 0;

use strict;
## Pretty output methods
sub show_status {
    my $status = shift;
    $status->{'N/A'} = 'N/A';
    show_bar('=');
    say(_c_('bold cyan'),
        $status->{name},
        _c_('reset'),
        _c_('cyan'),
        sprintf('[%s] :: %s',$status->{id},scalar localtime()),
        _c_('reset'));
    show_bar('-');
    say(_c_('green'),
        sprintf("%-10s %8s /%8s %11s %4s   %s",'Resource','Stored','Capacity','Production','Full','Hours (until full)'),
        _c_('reset'));
    for my $res (qw(food ore water energy waste happiness)) {
        my $pct_full = !$status->{$res .'_capacity'} ? 0 : ($status->{"$res\_stored"} / $status->{"$res\_capacity"})*100;
        printf "%s%-10s%s:%s %7d %s/%s %7s %s(%s%6d%s/hr)%s %s %s %s%s\n",
            _c_('bold green'),
            ucfirst($res),
            _c_('reset')._c_('green'),
            _c_('bold yellow'),
            $status->{ $res eq 'happiness' ? $res : "$res\_stored" }, 
            _c_('reset')._c_('yellow'),
            _c_('bold'), 
            $status->{ $res eq 'happiness' ? 'N/A' : "$res\_capacity" }, 
            _c_('reset')._c_('cyan'),
            _c_('bold cyan'), 
            $status->{ "$res\_hour" },
            _c_('reset')._c_('cyan'),
            _c_('bold '.($pct_full > 95 ? 'red' : $pct_full > 80 ? 'yellow' : 'green')), 
            $res eq 'happiness' ? '  --' : sprintf('%3d%%',$pct_full),
            _c_('cyan'),
            $res eq 'happiness' ? '    --' : sprintf('% 6.1f',($status->{"$res\_capacity"} - $status->{"$res\_stored"})/$status->{"$res\_hour"}),
            _c_('reset');
    }
    show_bar('-');
}

sub upgrade_report {
    my ($status,$build_above,@buildings) = @_;
    show_bar('=');
    say(_c_('bold yellow'),"Upgrade Options Report",_c_('reset'));
    show_bar('-');
    printf "%7s %15s %2s %3s %7s %7s %7s %7s %s\n","ID","Type","Lv","Can","Food","Ore","Water","Energy","Waste";
    show_bar('-');
    printf "%s%-30s %7s %7s %7s %7s      --%s\n",_c_('bold green'),"Build Above",@{$build_above}{qw(food ore water energy)},_c_('reset');
    printf "%s%-30s %7s %7s %7s %7s %7s%s\n",_c_('bold green'),"Avail. For Build",
        (map { $status->{"$_\_stored"} - $build_above->{$_} } qw(food ore water energy)),
        $status->{"waste_capacity"} - $status->{"waste_stored"},
        _c_('reset');
    show_bar('-');
    for my $bldg (@buildings) {
        my $up = $bldg->{upgrade};
        print _c_('cyan');
        printf "%7s %15s %2s %3s %7s %7s %7s %7s %7s\n",$bldg->{id},substr($bldg->{pretty_type},0,15),$bldg->{level},$up->{can} ? 'YES' : 'NO',map {$up->{cost}->{$_} } qw(food ore water energy waste);
        print _c_('reset');
    }
    if (not scalar @buildings) {
        say(_c_('bold red'),'No pertinent buildings found on this colony.',_c_('reset'));
    }
    show_bar('-');
}

sub ship_report {
    my ($info, $sort) = @_;
    $sort = [qw(location type task)] if not defined $sort;
    my @ships;
    for my $pname (keys %$info) {
        push @ships, map { $_->{location} = $pname; $_ } @{$info->{$pname}};
    }
    my $reverse;

    @ships = sort {
        my $result;
        for my $s (@$sort) {
            my $reverse = $s =~ s/^-//g;
            if ( $s eq 'speed'
              || $s eq 'hold_size'
              || $s eq 'stealth'
              || $s eq 'combat'
            ) {
                $result = $a->{$s} <=> $b->{$s};
            } else {
                $result = $a->{$s} cmp $b->{$s};
            }
            return ($result * ($reverse ? -1 : 1)) if ($result != 0);
        }
        return 0;
    } @ships;

    show_bar('=');
    say(_c_('bold green'),"Ship Report",_c_('reset'));
    show_bar('-');
    printf("%-12s %-12s %-12s %7s %5s %5s %6s  %s\n",qw(Name Type Location Cargo Speed Stlh combat Status));
    for my $ship (@ships) {
         my $task = $ship->{task};
         my $status_string;
         if ($task eq 'Docked') {
            $status_string = _c_('bold green')."Docked";
         } 
         elsif ($task eq 'Travelling') {
            $status_string = _c_('bold cyan')."Travelling"._c_('reset');
            #_c_('green').sprintf("\n%s%s -> %s, arriving %s",(' 'x13),$ship->{from}->{name},$ship->{to}->{name},$ship->{date_arrives});
         }
         elsif ($task eq 'Mining') {
            $status_string = _c_('bold yellow')."Mining";
         }
         elsif ($task eq 'Building') {
            $status_string = _c_('bold red')."Building";
         } 
         else {
            $status_string = _c_('bold magenta').$task
         }
         $status_string .= _c_('reset');

         printf("%s%-12s %s%-12s %s%-12s %s%7s %5s %5s %6s  %s\n",
             _c_('bold yellow'),substr($ship->{name},    0,12),
             _c_('bold green') ,substr($ship->{type},    0,12),
             _c_('bold cyan')  ,substr($ship->{location},0,12),
             _c_('reset')      ,$ship->{hold_size},
             $ship->{speed},
             $ship->{stealth},
             $ship->{combat},
             $status_string
         );
    }
    show_bar('=');
}

sub mission_list {
    use Text::Wrap;
    $Text::Wrap::columns = 78;
    my ($planet,$terse,@missions) = @_;
    show_bar('=','bold black');
    say(_c_('bold yellow')."$planet Mission Command"._c_('reset'));
    show_bar('-','bold black');
    for (@missions) {
        say(_c_('bold white').sprintf("[%d] %s",$_->{id},$_->{name}));
        say(_c_('bold blue'),'Max Uni.: ',_c_('bold cyan'),$_->{max_university_level},
            _c_('reset')._c_('bold blue'),', Posted: ',_c_('bold cyan'),$_->{date_posted});
        my @objectives = @{$_->{objectives}};
        my @rewards   = @{$_->{rewards}};
        if (not $terse) {
            say(_c_('reset').wrap('','',$_->{description}));
            say(_c_('bold white')."\nObjectives:");
            for (@objectives) {
                say(_c_('bold yellow').$_);
            }
            say(_c_('bold white')."\nRewards:");
            for (@rewards) {
                say(_c_('bold green').$_);
            }
        } else {
            say(_c_('bold white')."Objectives: "._c_('bold yellow').join(q{, },@objectives));
            say(_c_('bold white')."Rewards: "._c_('bold green').join(q{, },@rewards));
        }
        show_bar('-','bold black');
    }
}   

sub production_report { 
    # Takes a list of hashrefs, each is the "building" portion of view()
    my @buildings = @_; 
    show_bar('=','magenta');
    say(_c_('bold magenta').'Production Report (Per Hour)');
    show_bar('-','magenta');
    printf("%20s %2s %6s %6s %6s %6s %6s %6s\n",
        'Building Type','Lv',
        qw(Food Ore Water Energy Happy Waste));
    @buildings = sort { production_sum($b) <=> production_sum($a) 
                        || $a->{waste_hour} <=> $b->{waste_hour} } 
                        @buildings;
    my $gross;
    for my $building (@buildings) {
        printf("%s%20s %2s %s%6s %s%6s %s%6s %s%6s %s%6s %s%6s%s\n",
            _c_('bold yellow'),
            substr($building->{name},0,20),
            $building->{level},
            (map { color_code($building->{"$_\_hour"}) } 
                qw(food ore water energy happiness)),
            color_code($building->{waste_hour},1), #reverse color coding
            _c_('reset'),
        );
        for my $res (qw(food ore water energy happiness waste)) {
            my $rate = $building->{"$res\_hour"};
            if ($rate > 0) {
                $gross->{production}->{$res} += $rate;
            }
            elsif ($rate < 0) {
                $gross->{consumption}->{$res} += $rate;
            }
        }
    }
    show_bar('-','magenta');
    for my $type (qw(production consumption)) {
        printf("%s%20s %2s %s%6s %s%6s %s%6s %s%6s %s%6s %s%6s%s\n",
            _c_('bold yellow'),
            "Gross $type",
            '',
            (map { color_code($gross->{$type}->{$_}) } 
                qw(food ore water energy happiness waste)),
            _c_('reset'),
        );
    }
    show_bar('-','magenta');
}

sub trade_list {
    show_bar('-','green');
    printf("%15s %10s %15s %10s %10s %s\n",
        'Empire',
        'Ratio',
        'Asking',
        'Offering',
        'Quantity',
        'Description',
    );
    for my $item (@_) {
        my $rt = $item->{real_type};
        my ($desc) = $item->{offer_description} =~ m/^(?:\d+\s)?(.+)/imxg;
        printf("%s%15s %s%10s %s%15s %s%10s %10i %s\n",
            _c_('bold cyan'),
            substr($item->{empire}->{name},0,15),
            _c_('reset')._c_('cyan'),
            $item->{ratio},
            _c_('reset'),
            substr($item->{ask_description},0,15),
            _c_($rt eq 'food' ? 'bold green' :
                $rt eq 'ore'  ? 'bold yellow' :
                $rt eq 'water' ? 'bold blue' :
                $rt eq 'energy' ? 'bold cyan' :
                $rt eq 'glyph' ? 'bold magenta' :
                $rt eq 'plan' ? 'magenta' :
                $rt eq 'waste' ? 'bold red' :
                $rt eq 'ship' ? 'bold white' :
                'reset'),
            $rt,
            $item->{offer_quantity},
            $desc,
        );
    }
    show_bar('-','green');
}

sub color_code {
    my ($val, $reverse) = @_;
    $val = 0 if not defined $val;
    my $original = $val;
    $val *= -1 if $reverse;
    return ((($val > 0) ? _c_('bold green') 
           : ($val < 0) ? _c_('bold red') 
           : _c_('white')),$original);
}

sub production_sum {
    my $building = shift;
    return sum( 
        @{$building}{
            map { "$_\_hour" } 
            qw(food water ore energy happiness)
        }
    );
}

sub message {
    my @messages = @ARG;;
    say(_c_('bold blue'),' (*) ',_c_('cyan'),@messages,_c_('reset'));
}

sub warning {
    my @messages = @ARG;;
    say(_c_('bold red'),' <!> ',_c_('yellow'),@messages,_c_('reset'));
}

sub action {
    my @messages = @ARG;;
    say(_c_('bold green'),' [+] ',_c_('white'),@messages,_c_('reset'));
}

sub trace {
    my @messages = @ARG;;
    say(_c_('blue'),'   .oO( ',_c_('cyan'),@messages,_c_('blue'),' )',_c_('reset'));
}

sub show_bar {
    my $char = shift;
    my $color = shift || 'blue';
    say(_c_($color),($char x 72),_c_('reset'));
}

sub say  {
    print @_,"\n"; 
}

sub _c_ {
    if (-t STDOUT && $ansi_color) {
        return color(@_);
    }
    return '';
}

sub phours {
    return ptime( $ARG[0] * 3_600 );
}

sub ptime {
    my $sec = shift;
    my ($d, $h, $m, $s);
    $d  = int( $sec / 86_400 );
    $sec = $sec % 86_400;
    $h  = int( $sec / 3_600 );
    $sec = $sec % 3_600;
    $m  = int( $sec / 60 );
    $s  = $sec % 60;
    my $time = sprintf q{%02d:%02d:%02d:%02d}, $d, $h, $m, $s;
    $time =~ s/^[0:]+//;
    return $time;
}

sub surface {
    my $surface_type = shift;
    my $building_hash = shift;
    my $buildings = [values %$building_hash];
    my @map_x = (-5,-4,-3,-2,-1,0,1,2,3,4,5);
    my @map_y = reverse @map_x;

    print "   |".join(q{|},map { sprintf("%2s ",$_) } @map_x )."\n";
    print "___".('|___' x 11)."\n";
    for my $map_y (@map_y) {
        printf "%2s |",$map_y;
        surface_line('label',$surface_type,$buildings,$map_y,@map_x);
        print "\n";
        print "___|";
        surface_line('level',$surface_type,$buildings,$map_y,@map_x);
        print "\n";
    }
}

sub surface_line {
    my ($mode,$surface,$buildings,$map_y,@map_x) = @_;

    for my $map_x (@map_x) {
        my ($building) = grep { $_->{x} == $map_x && $_->{y} == $map_y } @$buildings;
        if (not $building) {
            my ($s1,$s2) = @{surface_types()->{surface}->{$surface}};
            print (($mode eq 'label' ? $s1 : $s2) . _c_('reset'));
            next;
        }
        my $btype = Games::Lacuna::Client::Buildings::type_from_url($building->{url});
        my $types = surface_types();
        my $found = 0;
        for my $type (keys %$types) {
            if(exists $types->{$type}->{$btype}) {
                $found = 1;
                print _c_($type eq 'command' ? 'bold white' :
                          $type eq 'food'    ? 'bold green' :
                          $type eq 'glyph'   ? 'bold magenta' :
                          $type eq 'energy'  ? 'bold cyan' :
                          $type eq 'ore'     ? 'bold yellow' :
                          $type eq 'waste'   ? 'bold red' :
                          $type eq 'water'   ? 'bold blue' :
                          'reset');
                 if ($mode eq 'label') {
                    print $types->{$type}->{$btype};
                 } else {
                    printf("%2d ",$building->{level});
                 }
             }
        }
        print "???" if not ($found);
        print _c_('reset')." ";
    }
}

sub surface_types {
    return {
        surface => {
            p1  => [_c_('yellow').' .  ',_c_('green')  .'` . '],
            p2  => [_c_('red')   .'\_/ ',_c_('red')    .'/ \_'],
            p3  => [_c_('bold yellow').' .  ',_c_('white')  .': : '],
            p4  => [_c_('white') .' .  ',_c_('magenta').'. . '],
            p5  => [_c_('bold yellow').'\_/  ',_c_('green')  .'/ \_'],

            p6  => [_c_('yellow').' .  ',_c_('bold black').'. . '],
            p7  => [_c_('magenta').' .  ',_c_('white').'` . '],
            p8  => [_c_('bold black').' .  ',_c_('bold black').'. . '],
            p9  => [_c_('white').' .  ',_c_('green').'. . '],
            p10 => [_c_('yellow').' :  ',_c_('yellow').': : '],

            p11 => [_c_('green').' .  ',_c_('yellow').'. . '],
            p12 => [_c_('bold green').' .  ',_c_('green').'` . '],
            p13 => [_c_('white').' :  ',_c_('white').': : '],
            p14 => [_c_('bold black').' .  ',_c_('white').'. . '],
            p15 => [_c_('red').' .  ',_c_('yellow').'. . '],

            p16 => [_c_('red').' .  ',_c_('yellow').'` . '],
            p17 => [_c_('cyan').' .  ',_c_('bold green').'` . '],
            p18 => [_c_('cyan').' .  ',_c_('white').'. . '],
            p19 => [_c_('bold blue').' .  ',_c_('cyan').'. . '],
            p20 => [_c_('bold black').' .  ',_c_('yellow').'. . '],
        },
        command => {
            Archaeology          => 'Arc',
            Development          => 'Dev',
            Embassy              => 'Emb',
            Intelligence         => 'Int',
            Network19            => 'N19',
            Observatory          => 'Obs',
            Park                 => 'Prk',
            PlanetaryCommand     => 'PCC',
            Security             => 'Sec',
            Shipyard             => 'Shp',
            SpacePort            => 'Spc',
            Trade                => 'Trd',
            Transporter          => 'SST',
            Capitol              => 'Cap',
            CloakingLab          => 'Clk',
            Entertainment        => 'Ent',
            Espionage            => 'EsM',
            GasGiantLab          => 'Gas',
            GasGiantPlatform     => 'GPl',
            GeneticsLab          => 'GeL',
            LuxuryHousing        => 'Lux',
            MissionCommand       => 'Mis',
            MunitionsLab         => 'Mun',
            Oversight            => 'OvM',
            PilotTraining        => 'Pil',
            Propulsion           => 'Pro',
            Stockpile            => 'Stk',
            TerraformingLab      => 'Ter',
            TerraformingPlatform => 'TPl',
            University           => 'Uni',
        },
        food => {
            Algae     => 'Alg',
            Apple     => 'App',
            Bean      => 'Bn ',
            Beeldeban => 'Bdb',
            Bread     => 'Brd',
            Burger    => 'Brg',
            Cheese    => 'Chz',
            Chip      => 'Chp',
            Cider     => 'Cid',
            Corn      => 'Crn',
            CornMeal  => 'CMl',
            Dairy     => 'Dry',
            Denton    => 'Den',
            Lapis     => 'Lap',
            Malcud    => 'Mal',
            Pancake   => 'Pan',
            Pie       => 'Pie',
            Potato    => 'Pot',
            Shake     => 'Shk',
            Soup      => 'Sup',
            Syrup     => 'Syr',
            Wheat     => 'Whe',
        },

        glyph => {
            Crater                => '(_)',
            CrashedShipSite       => '{S}',
            EssentiaVein          => '/E\\',
            GeoThermalVent        => '/G\\',
            InterDimensionalRift  => '\I/',
            KalavianRuins         => '{K}',
            Lake                  => 'oO*',
            Lagoon                => '(O)',
            LibraryOfJith         => '{J}',
            Grove                 => '*%*',
            MassadsHenge          => '{M}',
            NaturalSpring         => '/N\\',
            OracleOfAnid          => '{O}',
            RockyOutcrop          => '}:.',
            Ravine                => '\R/',
            Sand                  => ':::',
            TempleOfTheDrajilites => '{D}',
            Volcano               => '/V\\',
        },
        energy => {
            Fission     => 'Fis',
            Fusion      => 'Fus',
            Geo         => 'Geo',
            HydroCarbon => 'HC ',
            Singularity => 'Sin',
            WasteEnergy => 'WsE',
        },
        ore => {
            Mine           => 'Min',
            OreRefinery    => 'ORf',
            WasteDigester  => 'WsD',
            MiningMinistry => 'MnM',
        },
        waste => {
            WasteTreatment => 'WsT',
            WasteRecycling => 'Rcy',
        },
        water => {
            WaterProduction   => 'WPo',
            WaterPurification => 'WPu',
            WaterReclamation  => 'WRe',
        },
        storage => {
            WasteSequestration => 'WsS',
            EnergyReserve      => 'EnR',
            WaterStorage       => 'Wat',
            FoodReserve        => 'Foo',
            OreStorage         => 'Ore',
        },
    };

}

1;
