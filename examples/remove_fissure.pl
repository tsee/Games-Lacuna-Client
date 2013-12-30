#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Getopt::Long          (qw(GetOptions));

my @planets;
my $remove;
my $rpc_sleep = 1;
my $help;
my $cfg_file = 'lacuna.yml';

$cfg_file = shift(@ARGV) if @ARGV and $ARGV[0] !~ /^\-/;
GetOptions(
    'planet=s@'          => \@planets,
    'remove|demolish'    => \$remove,
    'sleep'              => \$rpc_sleep,
    'help'               => \$help,
    'config'             => \$cfg_file,
);

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

my $glc = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
        prompt_captcha => 1,
        rpc_sleep => $rpc_sleep,
	# debug    => 1,
);

usage() if $help or scalar @planets == 0;

# Load the planets
my $empire  = $glc->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Scan each planet
for my $pname ( sort keys %planets ) {
   next if ( scalar @planets and !( grep { lc $pname eq lc $_ } @planets ) );

    # Load planet data
    my $planet    = $glc->body( id => $planets{$pname} );
    my $result    = $planet->get_buildings;
    
    my $buildings = $result->{buildings};

    # Find the Deployed Bleeders
    my @fissures = grep {
            $buildings->{$_}->{url} eq '/fissure'
    } keys %$buildings;
    
    if (@fissures) {
        printf "%s has %d fissures\n", $pname, scalar(@fissures);
        
        if ($remove) {
            for my $id (@fissures) {
                my $fissure = $glc->building( id => $id, type => 'Fissure' );
                my $done = 0;
                my $downstat;
                do {
                  my $ok = eval { $downstat = $fissure->downgrade; };
                  if ($ok) {
                    print "Fissure downgraded to level ".$downstat->{building}->{level}."\n";
                    if ($downstat->{building}->{level} == 1) {
                      print "Demolishing Fissure.\n";
                      $ok = eval { $fissure->demolish; };
                      $done = 1;
                    }
                  }
                  else {
                    my $error = $@;
                    if ($error eq "RPC Error (1013): Unless your Fissure maintenance equipment is 100% operational, it is just too dangerous to attempt.") {
                      $ok = eval { $fissure->repair; };
                      if ($ok) {
                        print "Repaired fissure\n";
                      }
                      else {
                        print $error,"\n";
                        $done = 1;
                      }
                    }
                    else {
                      print $error,"\n";
                      $done = 1;
                    }
                  }
                } until $done;
            }
        }
        
        print "\n";
    }
}

sub usage {
    print STDERR <<END;
Usage: $0 [options]

This script will remove fissures from your colonies provided
there is enough ore to repair and seal them.

Options:

  --config <file> - GLC config, defaults to lacuna.yml
  --planet <name> - Build only on the specified planet(s)
  --remove
  --demolish
  'sleep'              => \$sleep,
  --help
END

    exit 1;
}
