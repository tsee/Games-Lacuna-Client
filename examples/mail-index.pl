#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use FindBin;
use Getopt::Long qw(GetOptions);
use JSON::Any;
use List::Util   qw( min );
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my %opts = (
    dbfile       => "$FindBin::Bin/../mail.db",
    'start-page' => 1,
    'max-pages'  => 1000,
    'max-rpc'    => 9500,
);

my @tags = qw(
    tutorial
    correspondence
    medal
    intelligence
    alert
);

GetOptions(
    \%opts,
    'archived',
    'start-page=i',
    'newest',
    'max-pages=i',
    'max-rpc=i',
    'dbfile=s',
    'help|h',
    'debug',
    @tags,
);

usage() if $opts{help};

@tags = grep {
        $opts{$_}
    } @tags;

# this number isn't returned by the server - but may change per-server?
my $msgs_per_page = 25;

die "dbfile not found: '$opts{dbfile}'\n"
    if !-e $opts{dbfile};

if ( $opts{newest} && $opts{'start-page'} != 1 ) {
        warn <<MSG;
Can't provide both --newest and --start-page options at the same time.
MSG

    usage();
}

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

my $dbfile = $opts{dbfile};

if ( $opts{debug} ) {
    warn "DEBUG: Using dbfile: '$dbfile'\n";
}

my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$dbfile",
    undef,
    undef,
    {
        RaiseError         => 1,
        ShowErrorStatement => 1,
    }
);

my $json = JSON::Any->new;

my $client = Games::Lacuna::Client->new(
	cfg_file  => $cfg_file,
    rpc_sleep => 1,
	# debug    => 1,
);

my $inbox = $client->inbox;
my $newest;

if ( $opts{newest} ) {
    $newest = most_recent_id();

    if ( $opts{debug} ) {
        warn "DEBUG: most recent mail id: $newest\n";
    }
}

my $from_page   = $opts{'start-page'};
my $to_page     = $from_page + $opts{'max-pages'} - 1;
my $total_pages = 0;
my $response;

for my $page ( $from_page .. $to_page ) {
    $total_pages++;

    get_page( $page )
        or last;
}

# summary
my $page_str = $total_pages == 1 ? 'page'
             :                     'pages';

print <<MSG;
Downloaded $total_pages $page_str of message headers

MSG

my $total_processed = $to_page * $msgs_per_page;
my $total_messages  = $response->{message_count};

if ( !$newest && $total_messages > $total_processed ) {

    my $remaining = $total_messages - $total_processed;
    my $next_page = $to_page + 1;

    print <<MSG;
There are $remaining more messages that have not yet been downloaded,
suggest re-running with option: --start-page $next_page

MSG
}

my $rpc_use   = $response->{status}{empire}{rpc_count};
my $rpc_avail = $response->{status}{server}{rpc_limit};

print <<MSG;
Current RPC usage: $rpc_use/$rpc_avail
MSG

exit;


###
sub most_recent_id {
    my $sql = "SELECT id FROM mail_index ORDER BY id DESC LIMIT 1";

    my @newest = $dbh->selectrow_array( $sql );

    return $newest[0];
}

sub get_page {
    my ( $page_id ) = @_;

    $page_id ||= 1;

    if ( $opts{debug} ) {
        warn "DEBUG: Fetching page: $page_id\n";
    }

    my %options = (
        page_number => $page_id,
    );

    $options{tags} = [@tags]
        if @tags;

    my $method = $opts{archived} ? 'view_archived'
               :                   'view_inbox';

    $response = $inbox->$method( \%options );

    save_to_db();

    check_msg_count( $page_id )
        or return;

    check_newest()
        or return;

    check_rpc_limit()
        or return;

    return 1;
}

sub save_to_db {
    my $insert_sth = $dbh->prepare_cached( <<SQL
INSERT OR REPLACE INTO mail_index
( id, subject, date_sent, from_name, from_id, to_name, to_id,
  has_read, has_replied, body_preview, has_archived, tags_json )
VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
SQL
    );

    my @fields = qw( id subject date from from_id to to_id has_read has_replied body_preview );

    for my $mail ( @{ $response->{messages} } ) {

        if ( $opts{debug} ) {
            warn "DEBUG:     Inserting message: $mail->{id}\n";
        }

        my $has_archived = $opts{archived} ? 1 : undef;
        my $tags_json    = $json->Dump( $mail->{tags} );

        $insert_sth->execute(
            @{$mail}{@fields},
            $has_archived,
            $tags_json,
        );
    }
}

sub check_msg_count {
    my ( $page_id ) = @_;

    my $msg_count = $response->{message_count};

    if ( $opts{debug} ) {
        warn "DEBUG: message_count: $msg_count\n";
    }

    if ( !$msg_count ) {
        print <<MSG;
No messages to download

MSG
        return;
    }

    my $processed = $msgs_per_page * $page_id;

    if ( $processed >= $msg_count) {
        print <<MSG;
Finished downloading all messages

MSG
        return;
    }

    return 1;
}

sub check_newest {
    return 1 if !$newest;

    my $oldest_fetched =
        min
        map {
            $_->{id}
        } @{ $response->{messages} };

    if ( $newest >= $oldest_fetched ) {

        if ( $opts{debug} ) {
            warn "DEBUG: Caught up with already-downloaded mail\n";
        }

        return;
    }

    return 1;
}

my $server_rpc_limit;

sub check_rpc_limit {
    # only need to check this once
    if ( !$server_rpc_limit ) {
        $server_rpc_limit = $response->{status}{server}{rpc_limit};

        if ( $server_rpc_limit < $opts{'max-rpc'} ) {
            warn <<MSG;
Warning:
--max-rpc is set higher than the rpc-limit returned by the server,
this may result in you running out of calls for the day.

MSG
        }
    }

    my $rpc_count = $response->{status}{empire}{rpc_count};

    if ( $rpc_count >= $opts{'max-rpc'} ) {
        print <<MSG;
Error:
Have exceeded --max-rpc : currently used $rpc_count

MSG
        return;
    }

    return 1;
}

sub usage {
  die <<END_USAGE;
Usage: $0 CONFIG_FILE
    --archived     # Download index from archive - default is inbox
    --start-page X # Defaults to 1 - allows you to pick-up where it finished
                   # if a previous run did not download all messages
    --newest       # If you've already previously downloaded all messages,
                   # and want it to stop as soon as it encounters a message
                   # it's already seen
    --max-pages X  # Defaults to 500 - consider daily RPC limit
    --max-rpc X    # Defaults to 4500 - will not continue if the RPC count
                   # returned by the server exceeds this number
    --dbfile PATH  # Defaults to mail.db in the current directory
    --help         # Print help message and exit
    --debug        # Print verbose diagnostics

    # To restrict the downloads to only messages with certain tags,
    # you may provide any of the following 5 options
    --tutorial
    --correspondence
    --medal
    --intelligence
    --alert

Downloads mail headers from inbox or archive.

The dbfile must already exist; it can be created by running:
    sqlite3 mail.db < examples/mail.sql

END_USAGE

}
