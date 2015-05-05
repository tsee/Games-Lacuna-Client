#!/usr/bin/env perl
# RPC, Captcha awareness added.
# Minimum and Maximum spy ratings added as well so you don't risk low rated spies first.
#
use strict;
use warnings;
use Getopt::Long          qw(GetOptions);
use List::Util            qw( first );
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use JSON;
use DateTime;
use Date::Parse;
use Date::Format;

  my $planet_name;
  my $target;
  my $tid;
  my $task;
  my $min_off = 0;
  my $min_def = 0;
  my $max_off = 10000;
  my $max_def = 10000;
  my $number  = 10000;
  my $random_bit = int rand 9999;
  my $dumpfile = "log/spy_run.js"; 
#.time2str('%Y%m%dT%H%M%S%z', time)."_$random_bit.js";
  my $fail_break = 0;
  my $fail = 0;
  my $sleep = 1;
  my $busy;
  my $dryrun;
  my $cfg_file = "lacuna.yml";
  my $help;
  my $name;
  my $flip = 0;

  GetOptions(
    'from=s'       => \$planet_name,
    'fail_break=i' => \$fail_break,
    'config=s'     => \$cfg_file,
    'dumpfile=s'   => \$dumpfile,
    'target=s'     => \$target,
    'tid=i'        => \$tid,
    'task=s'       => \$task,
    'name=s',      => \$name,
    'min_off=i'    => \$min_off,
    'min_def=i'    => \$min_def,
    'max_off=i'    => \$max_off,
    'max_def=i'    => \$max_def,
    'number=i'     => \$number,
    'busy'         => \$busy,
    'sleep=i'      => \$sleep,
    'dryrun'       => \$dryrun,
    'flip=i'         => \$flip,
    'help'         => \$help,
  );

  usage() if $help || !$planet_name || (!$target and !$tid) || !($task or $flip) || ($task and $flip);

  my $tstr;
  my $tvar;
  if (defined($tid)) {
    $tvar = $tid;
    $tstr = "body_id";
  }
  else {
    $tvar = $target;
    $tstr = "name";
  }
  if ($flip > 0) {
    $task = "Incite Rebellion";
  }

  my $task_list = task_list();
  unless (grep { $_ =~ /^$task/i } @{$task_list}) {
    print "$task not valid\n";
    print join("\n", @{$task_list}),"\n";
    die "You must pick a valid task\n";
  }

  unless ( $cfg_file and -e $cfg_file ) {
    $cfg_file = eval{
      require File::HomeDir;
      require File::Spec;
      my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
      File::Spec->catfile(
        $dist,
        'lacuna.yml'
      ) if $dist;
    };
    unless ( $cfg_file and -e $cfg_file ) {
      die "Did not provide a config file";
    }
  }

  my $json = JSON->new->utf8(1);
  my $df;
  open($df, ">", "$dumpfile") or die "Could not open $dumpfile\n";

  my $glc = Games::Lacuna::Client->new(
                 cfg_file => $cfg_file,
                 prompt_captcha => 1,
                 rpc_sleep => $sleep,
                 # debug    => 1,
               );

# Load the planets
  my $empire  = $glc->empire->get_status->{empire};
  my $insurrect_value = $empire->{insurrect_value} ? $empire->{insurrect_value} : 400_000_000_000_000_000;

  my $rpc_cnt_beg = $glc->{rpc_count};
  print "RPC Count of $rpc_cnt_beg\n";

# reverse hash, to key by name instead of id
  my %planets = reverse %{ $empire->{colonies} };

  my $body      = $glc->body( id => $planets{$planet_name} );
  my $buildings = $body->get_buildings->{buildings};

  my $intel_id = first {
         $buildings->{$_}->{url} eq '/intelligence'
       }
       grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
       keys %$buildings;


  my $intel = $glc->building( id => $intel_id, type => 'Intelligence' );

  my (@spies, $page, $done);

  my $spies = $intel->view_all_spies();
  print scalar @{$spies->{spies}}," spies found from ministry!\n";
  my @trim_spies;
  for my $spy (@{$spies->{spies}}) {
    next if lc( $spy->{assigned_to}{$tstr} ) ne lc( $tvar );
    next unless ($spy->{is_available});
    next if (!$busy and $spy->{assignment} ne 'Idle');
    if ($name) {
#      print "Checking for \'$name\' against \'$spy->{name}\'\n";
      next unless $spy->{name} =~ /$name/i;
    }
    next unless ($spy->{offense_rating} >= $min_off and
                 $spy->{offense_rating} <= $max_off and
                 $spy->{defense_rating} >= $min_def and
                 $spy->{defense_rating} <= $max_def);
    my @missions = grep {
        $_->{task} =~ /^$task/i
    } @{ $spy->{possible_assignments} };
    next if !@missions;
    if ( @missions > 1 ) {
      warn "Supplied --task matches multiple possible tasks - skipping!\n";
      for my $mission (@missions) {
        warn sprintf "\tmatches: %s\n", $mission->{task};
      }
      last;
    }
    $task = $missions[0]->{task};
#    print "Pushing ".$spy->{name}." onto list.\n";
    push @trim_spies, $spy;
  }
  push @spies, @trim_spies;

  print scalar @spies," spies found from $planet_name available.\n";

  print $df $json->pretty->canonical->encode(\@spies);
  close $df;

  if ($dryrun) { die "bailing now"; }
  my $spy_run = 0;
  for my $spy (@spies) {
    my $return;
    
    eval {
        $return = $intel->assign_spy( $spy->{id}, $task );
    };
    if ($@) {
      warn "Error: $@\n";
      next;
    }
    
    my $msg_text = "";
    my $message;
    if ($return->{mission}{message_id}) {
      $message = get_message_info($glc, $return->{mission}{message_id})->{message};
    }
    if ($message) {
      $msg_text = $message->{body};
    }
    else {
      $message = {
                   body => "No Message",
                   subject => "No Subject",
                 };
    }
    $msg_text = "No Contact" if ($message->{subject} eq "No Contact");
    if ($flip or $task eq "Incite Insurrection") {
      my $chance = 0;
      if ($task eq "Incite Rebellion") {
        if ($message->{subject} eq "Created Disturbance" or $message->{subject} eq "Rebellion Started") {
          $msg_text =~ / them ([0-9,-]+) happiness, leaving them with ([0-9,-]+)./;
          $msg_text = "Cost: $1 ; Remain: $2";
          my $happy = $2;
          $happy =~ s/,//g;
          my $chance = int(abs($happy) * 100/$insurrect_value);
          $msg_text = $msg_text."; $chance% 100% at $insurrect_value";
          if ($chance >= $flip) {
            $msg_text = $msg_text." Starting Insurrections";
            $task = "Incite Insurrection";
          }
        }
        else {
          $msg_text =~ tr/\n/_/s;
        }
      }
      elsif ( $message->{subject} eq "Insurrection Failed" ) {
        $msg_text =~ / them at ([0-9,-]+) unhappiness and with our chances based off of ([0-9,-]+) giving us a ([0-9-]+)%/;
        $msg_text = "U: $1; I: $2; $3%";
        $return->{mission}{result} = "Almost";
      }
      elsif ( $message->{subject} eq "Insurrection Complete") {
        $msg_text = "Done!";
        $number = 0;
      }
      else {
        $msg_text =~ tr/\n/_/s;
      }
    }
    else {
      if ($return->{mission}{result} eq "Accepted") {
        $msg_text = "Running: $task";
      }
      else {
        $msg_text =~ tr/\n/_/s;
      }
    }
    $spy_run++;
    if ($return->{mission}{result} eq "Failure") {
      $fail++;
      $msg_text = $message->{subject};
    }
    printf "%3d %s %s %s %s\n",
        $spy_run,
        $spy->{name},
        $return->{mission}{result},
        $return->{mission}{reason},
        $msg_text;
    last if $fail_break && $fail >= $fail_break;
    last if $spy_run >= $number;
  }
  my $rpc_cnt_end = $glc->{rpc_count};
  print "RPC Count start: $rpc_cnt_beg\n";
  print "RPC Count final: $rpc_cnt_end\n";
  undef $glc;
exit;

sub get_message_info {
  my ($glc, $msg_id) = @_;

  return $glc->inbox->read_message($msg_id);
}

sub get_chance {
  my $message = shift;

  
}

sub task_list {
  my $possible = [
"Idle",
"Counter Espionage",
"Security Sweep",
"Gather Resource Intelligence",
"Gather Empire Intelligence",
"Gather Operative Intelligence",
"Hack Network 19",
"Sabotage Probes",
"Rescue Comrades",
"Sabotage Resources",
"Appropriate Resources",
"Assassinate Operatives",
"Sabotage Infrastructure",
"Sabotage Defenses",
"Sabotage BHG",
"Incite Mutiny",
"Abduct Operatives",
"Appropriate Technology",
"Incite Rebellion",
"Incite Insurrection",
"Intel Training",
"Mayhem Training",
"Politics Training",
"Theft Training",
"Political Propaganda",
"Bugout",
];
  return $possible;
}

sub usage {
  die <<"END_USAGE";
Usage: $0
    --config     FILE  default: lacuna.yml
    --from       PLANET
    --target     PLANET
    --tid        BODY_ID (Use either tid or target, not both)
    --task       MISSION
    --flip       NUM  Will run Incite Rebellion until NUM % chance of insurrection happens, and then runs Insurrection
    --name       Match name of spy, partial allowed
    --min_def    Minimum Defense Rating
    --min_off    Minimum Offense Rating
    --max_def    Maximum Defense Rating
    --max_off    Maximum Offense Rating
    --number     Max Number of Agents to use
    --fail_break Number of fails before giving up
    --dumpfile   FILE json dumpfile
    --busy       Use any available agents, otherwise will only use Idle
    --sleep      RPC sleep interval
    --dryrun     Do not actually run missions
    --help       This message

CONFIG_FILE  defaults to 'lacuna.yml'

--from is the planet that your spy is from.

--target is the planet that your spy is assigned to.
--tid    is the planet body id that your spy is assigned to. Usefull if target is a bunch of UTF8 chars.

--task must match one of the missions listed in the API docs:
    http://us1.lacunaexpanse.com/api/Intelligence.html

It only needs to be long enough to uniquely match a single available mission,
e.g. "gather op" will successfully match "Gather Operative Intelligence"

END_USAGE

}
