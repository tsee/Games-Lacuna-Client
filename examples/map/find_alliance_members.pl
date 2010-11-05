use strict;
use warnings;
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);

$| = 1;

my $config_file = shift @ARGV;
die if not defined $config_file or not -e $config_file;

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

my $rv = $client->alliance->find('The Understanding');
my $alliance = $rv->{alliances}[0];
die if not defined $alliance;

my $profile = $client->alliance(id => $alliance->{id})->view_profile();
print Dumper $profile;

my $members = $profile->{profile}{members};

print "Member ids:\n";
print $_->{id},"\n" for @$members;


