use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use AnyEvent;
use List::Util qw(first);
use XML::RSS::Parser;
use LWP::Simple 'get';
use DateTime;
use DateTime::Format::Strptime;
use lib 'lib';
use lib 'examples/map/lib';
use LacunaMap::DB;

$| = 1;

use constant MINUTE => 60;

my $DbFile = 'map.sqlite';
my @FeedUrls;
GetOptions(
  'd|dbfile=s' => \$DbFile,
  'f|feed=s@' => \@FeedUrls,
);

my $config_file = shift @ARGV || 'lacuna.yml';
die if not defined $config_file or not -e $config_file;

LacunaMap::DB->import(
  $DbFile,
  cleanup => 'VACUUM',
  readonly => 0,
);

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

# fetch min/max coords
my $empire = $client->empire->get_status->{empire};
output("Loading empire $client->{name}...");

if (@FeedUrls) {
  foreach my $url (@FeedUrls) {
    output("Importing feed at $url");
    import_feed($url);
  }
}
else {
  my %zone_feed_urls;
  my $planets = $empire->{planets};
  # Scan each planet
  foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};
    output("Loading planet $name...");

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    my $buildings = $result->{buildings};

    # Find the Network19
    my $n19_id = List::Util::first {
      $buildings->{$_}->{name} =~ /network\s*19/i;
    } keys %$buildings;

    if (not defined $n19_id) {
      output("This planet has no Network 19 Affiliate");
      next;
    }

    my $n19 = $client->building(type => 'Network19', id => $n19_id);
    my $news_result = $n19->view_news;
    my $feeds = $news_result->{feeds};
    $zone_feed_urls{$_} = $feeds->{$_} for keys %$feeds;
  }

  foreach my $zone (keys %zone_feed_urls) {
    output("Importing feed for zone $zone...");
    import_feed($zone_feed_urls{$zone});
  }
} # end if not explicit feed links


sub import_feed {
  my $feed_url = shift;
  my $text = get($feed_url);
  open my $fh, '<', \$text or die;
  my $p = XML::RSS::Parser->new;
  my $feed = $p->parse_file($fh);

  my $feed_title = $feed->query('/channel/title')->text_content;
  $feed_title =~ /Zone (-?\d+\|-?\d+) / or die "Can't parse zone from feed title: '$feed_title'";
  my $zone = $1;
  output("Feed is for zone $zone");

  my $date_parser = DateTime::Format::Strptime->new(
    pattern => '%a,%t%d%t%b%t%Y%t%H:%M:%S%t%Z',
    locale => 'en_US',
  );

  LacunaMap::DB->begin;
  foreach my $item ( $feed->query('//item') ) {
    my $node = $item->query('title');
    my $title = $node->text_content;
    my $date = $item->query('pubDate');
    #print '  '.$node->text_content;
    #print "\n";
    my $datestr = $date->text_content;
    my $ts = $date_parser->parse_datetime($datestr)->strftime('%s');
    my $known = LacunaMap::DB::News->count(
      'where zone = ? and title = ? and time = ?',
      $zone, $title, $ts
    );
    if (not $known) {
      output("New news item '$title'");
      my $news = LacunaMap::DB::News->new(
        zone => $zone,
        title => $title,
        time => $ts,
      );
      $news->insert;
      LacunaMap::DB::Bodies->update_from_news($client, $news);

    }
  } # end foreach news item
  LacunaMap::DB->commit;
}


sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}
