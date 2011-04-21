#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use IO::Interactive qw( is_interactive );
use List::Util   qw( first );
use Try::Tiny;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my @planet;
my @pass;
my $help;

GetOptions(
    'planet=s@' => \@planet,
    'pass=s@'   => \@pass,
    'help|h'    => \$help,
);

usage() if $help;

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

my $is_interactive = is_interactive();

my $client = Games::Lacuna::Client->new(
	cfg_file  => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

SS:
for my $name ( sort keys %planets ) {
    next if @planet && !grep { $name eq $_ } @planet;
    
    my $planet = $client->body( id => $planets{$name} );
    
    my $result = $planet->get_buildings;
    
    next if $result->{status}{body}{type} ne 'space station';
    
    printf "Space Station: %s\n\n", $result->{status}{body}{name};
    
    my $buildings = $result->{buildings};
    
    my $parliament_id = first {
            $buildings->{$_}->{url} eq '/parliament'
        } keys %$buildings;
    
    my $parliament = $client->building( id => $parliament_id, type => 'Parliament' );
    
    my $propositions;
    
    try {
        $propositions = $parliament->view_propositions->{propositions};
    }
    catch {
        warn "$_\n\n\n";
        no warnings 'exiting';
        next SS;
    };
    
    if ( ! @$propositions ) {
        print "No propositions\n\n\n";
        next;
    }
    
    for my $prop ( @$propositions ) {
        printf "%s\n", $prop->{description};
        printf "Proposed by: %s\n", $prop->{proposed_by}{name};
        printf "Will automatically pass at: %s\n", $prop->{date_ends};
        printf "Votes needed: %d\n", $prop->{votes_needed};
        printf "Votes so far: %d yes, %d no\n",
            $prop->{votes_yes},
            $prop->{votes_no};
        
        if ( exists $prop->{my_vote} ) {
            printf "You have already voted: %s\n\n",
                $prop->{my_vote} ? 'yes' : 'no';
            next;
        }
        
        my $vote;
        
        if ( @pass && first { $prop->{description} =~ /$_/i } @pass ) {
            print "AUTO-VOTED YES\n";
            $vote = 1;
        }
        elsif ( $is_interactive ) {
            while ( !defined $vote ) {
                print "Vote yes or no: ";
                my $input = <STDIN>;
                
                if ( $input =~ /y(es)?/i ) {
                    $vote = 1;
                }
                elsif ( $input =~ /no?/i ) {
                    $vote = 0;
                }
                else {
                    print "Sorry, don't understand - vote again\n";
                }
            }
        }
        else {
            print "Non-interactive terminal - skipping proposition\n";
            next;
        }
        
        $parliament->cast_vote( $prop->{id}, $vote );
        print "\n\n";
    }
}

exit;


sub usage {
    die <<"END_USAGE";
Usage: $0 CONFIG_FILE

Prompts for vote on each proposition.

Options:
    --planet SPACE-STATION NAME

Multiple --planet opts may be provided.
If no --planet opts are provided, will search for all allied space-stations.

    --pass REGEX
Multiple --pass opts may be provided - these are run as regexes against each
proposition description - if it matches, the proposition is automatically
voted 'yes'.

END_USAGE

}
