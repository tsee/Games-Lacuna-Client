#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw( GetOptions );
use List::Util   qw( first );

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my @planet;
my $help;

GetOptions(
    'planet=s@' => \@planet,
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

my $client = Games::Lacuna::Client->new(
	cfg_file  => $cfg_file,
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = map { $empire->{planets}{$_}, $_ } keys %{ $empire->{planets} };

for my $name ( keys %planets ) {
    next if @planet && !grep { $name eq $_ } @planet;
    
    my $planet = $client->body( id => $planets{$name} );
    
    my $result = $planet->get_buildings;
    
    next if $result->{status}{body}{type} ne 'space station';
    
    my $buildings = $result->{buildings};
    
    my $parliament_id = first {
            $buildings->{$_}->{url} eq '/parliament'
        } keys %$buildings;
    
    my $parliament = $client->building( id => $parliament_id, type => 'Parliament' );
    
    my $propositions = $parliament->view_propositions->{propositions};
    
    next if !@$propositions;
    
    printf "Space Station: %s\n\n", $result->{status}{body}{name};
    
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
        
        $parliament->cast_vote( $prop->{id}, $vote );
        print "\n";
    }
}

exit;


sub usage {
    die <<"END_USAGE";
Usage: $0 CONFIG_FILE

Prompts for vote on each proposition.

Options:
    --planet GAS-GIANT NAME

Multiple --planet opts may be provided.
If no --planet opts are provided, will search for all allied space-stations.

END_USAGE

}
