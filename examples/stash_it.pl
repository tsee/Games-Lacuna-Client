#!/usr/bin/perl

use warnings;
use strict;
use feature ':5.10';

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;

use Getopt::Long;
use List::Util qw(first);

my $cfg_file  = 'lacuna.yml';
my ($help, $arg_planet_name, $clean_arg_planet_name);
GetOptions(
    'cfg=s'    => \$cfg_file,
    'planet=s' => \$arg_planet_name,
    'h|help'   => \$help,
) or usage();
if ($arg_planet_name) {
    ($clean_arg_planet_name = lc($arg_planet_name)) =~ s/\W//g;
}

usage() if $help;

my $action = shift @ARGV;
usage('No action specified') unless $action;

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
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

# Scan each planet
my ($planet_name, $emb);
for my $name ( sort keys %planets ) {
    (my $clean_name = lc($name)) =~ s/\W//g;
    next if defined $clean_arg_planet_name and $clean_name ne $clean_arg_planet_name;

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};

    my $buildings = $result->{buildings};

    # Find the Embassy
    my $emb_id = first {
            $buildings->{$_}->{name} eq 'Embassy'
    } keys %$buildings;

    next unless $emb_id;

    $planet_name = $name;
    $emb = $client->building( id => $emb_id, type => 'Embassy' );
    last;
}

die "No embassy found" . ($arg_planet_name ? " on planet $arg_planet_name" : '') . "!\n"
    unless $emb;
print "Selected embassy on $planet_name for you, specify --planet to choose a different one.\n"
    unless $arg_planet_name;

my %ore_types = map { $_ => 1 } qw(
    anthracite bauxite beryl     chalcopyrite chromite
    fluorite   galena  goethite  gold         gypsum
    halite     kerogen magnetite methane      monazite
    rutile     sulfur  trona     uraninite    zircon
);

given ($action) {
    when('view') {
        my $stash = $emb->view_stash;

        my $remaining = $stash->{exchanges_remaining_today};
        my $max       = $stash->{max_exchange_size};

        print "Current stash:\n";
        if (keys %{$stash->{stash}}) {
            print "\n";
            my $energy = delete $stash->{stash}->{energy};
            my $water  = delete $stash->{stash}->{water};
            print "Energy: $energy\n" if $energy;
            print "Water:  $water\n" if $water;

            if (grep { $stash->{stash}->{$_} } keys %ore_types) {
                print "Ore:\n";
                for my $type (sort keys %ore_types) {
                    my $cnt = delete $stash->{stash}->{$type};
                    if ($cnt) {
                        print "  $cnt $type\n";
                    }
                }
            }

            if (grep { $stash->{stash}->{$_} } keys %{$stash->{stash}}) {
                print "Food:\n";
                for my $type (sort keys %{$stash->{stash}}) {
                    my $cnt = delete $stash->{stash}->{$type};
                    next unless $cnt;
                    print "  $cnt $type\n";
                }
            }
        }
        else {
            print "\tEmpty.\n";
        }

        print "\n";
        print "Your maximum exchange size is $max.\n";
        print "This embassy has $remaining exchanges remaining today.\n";
    }
    when('donate') {
        my $donation = {};
        while (@ARGV) {
            my $count = shift @ARGV;
            my $item = shift @ARGV;
            usage() unless defined $count and defined $item;
            $donation->{$item} = $count;
        }
        eval {
            $emb->donate_to_stash($donation);
        };
        if (my $e = $@) {
            die("Error donating: " . $e->text . "\n");
        }
    }
    when('exchange') {
        my ($exchange, $type);
        while (@ARGV) {
            my $count = shift @ARGV;
            given ($count) {
                when (['give','take']) {
                    $type = $_;
                }
                default {
                    usage() unless $type;

                    my $item = shift @ARGV;
                    usage() unless defined $item;

                    $exchange->{$type}->{$item} = $count;
                }
            };
        }
        usage() unless $exchange->{give} and $exchange->{take};

        eval {
            $emb->exchange_with_stash($exchange->{give}, $exchange->{take});
        };
        if (my $e = $@) {
            die("Error exchanging: " . $e->text . "\n");
        }
    }
    default {
        usage("Unknown action: $action");
    }
};

sub usage {
    my ($msg) = @_;
    print $msg ? "$0 - $msg\n" : "$0\n";
    print "Options:\n";
    print "\t--cfg=<filename>         Lacuna Config File, see examples/myaccount.yml\n";
    print "\t--planet=<name>          Specify a specific planet\n";
    print "\n";
    print "Actions:\n";
    print "\tview\n";
    print "\tdonate <count> <item>\n";
    print "\texchange give <count> <item> [...] take <count> <item> [...]\n";
    exit(1);
}

