#!/usr/bin/perl
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use List::Util   qw( first );
use Date::Parse;
use Date::Format;
use utf8;

  my %opts = (
    h          => 0,
    v          => 0,
    config     => "lacuna.yml",
    dumpfile   => "log/rearrange.js",
    layoutfile => "data/data_layout.js",
  );

  my $ok = GetOptions(\%opts,
    'planet=s',
    'help|h',
    'dumpfile=s',
    'config=s',
    'layoutfile',
  );

  unless ( $opts{config} and -e $opts{config} ) {
    $opts{config} = eval{
      require File::HomeDir;
      require File::Spec;
      my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
      File::Spec->catfile(
        $dist,
        'login.yml'
      ) if $dist;
    };
    unless ( $opts{config} and -e $opts{config} ) {
      die "Did not provide a config file";
    }
  }
  usage() if ($opts{h});
  if (!$opts{planet}) {
    print "Need name of planet to layout with --planet!\n";
    usage();
  }
  my $json = JSON->new->utf8(1);

  my $new_layout;
  if (-e $opts{layoutfile}) {
    my $lf;
    open($lf, "$opts{layoutfile}") || die "Could not read $opts{layoutfile}\n";
    my $lines = join("",<$lf>);
    $new_layout = $json->decode($lines);
  }
  else {
    print "Could not read $opts{layoutfile}\n";
    print "Create a JSON file with an array of hashes.\n";
    print "[ { id => building_id, x => new_x_pos, y => new_y_pos },\n",
          "[ { id => building_id, x => new_x_pos, y => new_y_pos },\n", 
          "...",
          "[ { id => building_id, x => new_x_pos, y => new_y_pos } ]\n", 
          "All buildings being moved must be listed.\n",
          "Do not overlap buildings.\n",
          "All parts of a Lost City or Space Station Lab must move.\n",
          "PCC and Station Command must be left at 0,0.\n";
  }
  my $ofh;
  open($ofh, ">", $opts{dumpfile}) || die "Could not create $opts{dumpfile}";

  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config},
    # debug    => 1,
  );

  my $data  = $glc->empire->view_species_stats();
  my $ename = $data->{status}->{empire}->{name};
  my $ststr = $data->{status}->{server}->{time};

# reverse hash, to key by name instead of id
  my %planets = map { $data->{status}->{empire}->{planets}{$_}, $_ }
                  keys %{ $data->{status}->{empire}->{planets} };

# Load planet data
  my $body   = $glc->body( id => $planets{$opts{planet}} );

  print "Rearranging...\n";
  my $result = $body->rearrange_buildings($new_layout);
  print "Done, refresh your browser to see it there...\n";

  print $ofh $json->pretty->canonical->encode($result);
  close($ofh);

  print "$glc->{total_calls} api calls made.\n";
  print "You have made $glc->{rpc_count} calls today\n";
exit; 

sub usage {
  die <<"END_USAGE";
Usage: $0 CONFIG_FILE
       --planet         PLANET_NAME
       --CONFIG_FILE    defaults to lacuna.yml
       --layoutfile     Input file, default data/data_layout.js
       --dumpfile       Output file, default log/rearrange.js
       --config         Lacuna Config, default lacuna.yml

END_USAGE

}
