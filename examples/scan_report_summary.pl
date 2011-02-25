#!/usr/bin/perl
#
# Grab all scan reports from your inbox and summarize them.
# Currently outputs text.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;

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

my $inbox = $client->inbox;

my $headers = $inbox->view_inbox()->{messages};
my @scan_msg_ids = grep { $_->{subject} eq 'Scan Results' } @$headers;

foreach my $id (@scan_msg_ids) {
     my $msg = $inbox->read_message($id)->{message};
     my($line) = $msg->{body} =~ /{([^}]+)}/;
     print $msg->{subject}, "\n";
     print "------------\n";
     print "$line\n";
     print join "\n", sort map { $_->{image} } @{ $msg->{attachments}{map}{buildings} };
     print "\n\n";
}
