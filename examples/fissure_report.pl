#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

  my %opts = (
        h => 0,
        v => 0,
        config => "lacuna.yml",
        dumpfile => "log/fissures.js",
        zone => '',
  );

  GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'config=s',
    'dumpfile=s',
    'zone=s',
  );

  usage() if $opts{h};
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  my $of;
  if ($opts{dumpfile} ne '') {
    open($of, ">", $opts{dumpfile}) || die "Could not open $opts{dumpfile} for writing";
  }

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  print "Starting RPC: $glc->{rpc_count}\n";

  my $args = {};
  $args->{session_id} = $glc->{session_id};
  if ($opts{zone} ne '') {
    $args->{zone} = $opts{zone};
  }

  my $return = $glc->map->probe_summary_fissures( $args );

  my $fissures = $return->{fissures};
  for my $fizz (keys %$fissures) {
    printf("%07d %05d:%05d %20s\n",
           $fizz, $fissures->{$fizz}->{x}, $fissures->{$fizz}->{y}, $fissures->{$fizz}->{name});
  }

  if ($opts{dumpfile} ne '') {
    print $of $json->pretty->canonical->encode($return);
    close($of);
  }
  print "Ending   RPC: $glc->{rpc_count}\n";

exit;

sub usage {
    diag(<<END);
Usage: $0 [options]

This program will list all fissures that are in systems probed by your alliance.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config <file>    - Specify a GLC config file, normally lacuna.yml.
  --zone             - Specify a zone to look at.  Default is all.
  --dumpfile         - data dump for all info
END
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
