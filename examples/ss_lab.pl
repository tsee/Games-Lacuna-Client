#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long   qw( GetOptions );
use List::Util     qw( first );
use Number::Format qw( format_number );

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Games::Lacuna::Client::PrettyPrint qw( ptime );

my %opts;

GetOptions(
    \%opts,
    'planet=s',
    'costs',
    'level=i',
    'type=s',
    'subsidize',
	'help|h',
);

usage() if $opts{help};
usage() if !exists $opts{planet};

usage() if ( $opts{level} && !$opts{type} )
        || ( $opts{type} && !$opts{level} );

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
my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Load planet data
my $body   = $client->body( id => $planets{ $opts{planet} } );
my $result = $body->get_buildings;

my $buildings = $result->{buildings};

# Find the SSLab
my $ssl_id = first {
        $buildings->{$_}->{url} eq '/ssla'
} keys %$buildings;

die "No SS Lab on this planet\n"
	if !$ssl_id;

my $sslab = $client->building( id => $ssl_id, type => 'SSLA' );


if ( $opts{type} || $opts{subsidize} ) {
    make_plan()
        if $opts{type};

    subsidize_plan()
        if $opts{subsidize};
}
elsif ( $opts{costs} ) {
    print_costs();
}
else {
    print_plans();
}

exit;


sub print_plans {
    my $status = $sslab->view->{make_plan};
    my $types  = $status->{types};

    foreach my $plan ( @$types ) {
        print "$plan->{name}\n";
    }

    if ( my $making = $status->{making} ) {
        print <<MAKING;

Already making plan:
$making
MAKING
    }
}

sub print_costs {
    my $status = $sslab->view->{make_plan};
    my $costs  = $status->{level_costs};
    my $level  = 1;

    for my $type ( @$costs ) {

        map {
            $type->{$_} = format_number( $type->{$_} )
        } qw( food ore water energy waste );

        $type->{time} = ptime( $type->{time} );

        print <<COSTS;
Level: $level
food:   $type->{food}
ore:    $type->{ore}
water:  $type->{water}
energy: $type->{energy}
waste:  $type->{waste}
time:   $type->{time}

COSTS

        $level++;
    }

    print "subsidy: $status->{subsidy_cost}E\n";
}

sub make_plan {
    my $status = $sslab->make_plan( $opts{type}, $opts{level} );

    print <<MAKING;
Making:
$status->{make_plan}{making}
MAKING
}

sub subsidize_plan {
    my $status = $sslab->subsidize_plan;

    print "Subsidized\n";
}


sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
    --planet PLANET_NAME    # REQUIRED
    --costs
    --level  LEVEL
    --type   PLAN
    --subsidize

CONFIG_FILE  defaults to 'lacuna.yml'

If no arguments are provided, it will print a list of plans that can be built,
and whether any plan is already being built.

If --costs opt is provided, will print costs of all level plans that can be
built.

If --level and --type opts are provided, it will start making that plan.
If --subsidize is also provided, the plan-build will be E-subsidized.

--subsidize as an only option, will E-subsidize any plan currently being made.

END_USAGE

}
