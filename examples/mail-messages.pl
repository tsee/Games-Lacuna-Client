#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use FindBin;
use Getopt::Long          qw(GetOptions);
use JSON::Any;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

my %opts = (
    dbfile         => "$FindBin::Bin/../mail.db",
    'max-messages' => 2000,
    'max-rpc'      => 9500,
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
    'max-messages=i',
    'max-rpc=i',
    'dbfile=s',
    'help|h',
    'debug',
    'dryrun|dry-run',
    @tags,
    'ok',
    'subject=s@',
);

usage() if $opts{help};

@tags = grep {
        $opts{$_}
    } @tags;

my @subject = $opts{subject} ? @{ $opts{subject} }
            :                  ();

usage() if !$opts{ok} && !@tags && !@subject;

die "dbfile not found: '$opts{dbfile}'\n"
    if !-e $opts{dbfile};

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

my @ids = filter_mail();

$#ids = $opts{'max-messages'}-1
    if @ids > $opts{'max-messages'};

if ( $opts{dryrun} ) {
    my $count = @ids;
    print "Would fetch $count messages\n";
    exit;
}

if ( $opts{debug} ) {
    my $count = @ids;
    print "Will fetch $count messages\n";
}

my $total_messages = 0;
my $response;

for my $mail_id (@ids) {
    $total_messages++;

    get_message( $mail_id )
        or last;
}

# summary
my $message_str = $total_messages == 1 ? 'message'
                :                        'messages';

print <<MSG;
Downloaded $total_messages $message_str

MSG

my $rpc_use   = $response->{status}{empire}{rpc_count};
my $rpc_avail = $response->{status}{server}{rpc_limit};

print <<MSG;
Current RPC usage: $rpc_use/$rpc_avail
MSG

exit;


###
sub filter_mail {
    my $sql = "SELECT mail_index.id FROM mail_index LEFT JOIN mail_message "
            . "ON mail_index.id = mail_message.id "
            . "WHERE mail_message.id IS NULL ";

    if ( @tags ) {
        $sql .= " AND (";

        $sql .= join " OR ",
                map {
                    "tags_json LIKE '%$_%'"
                }
                map {
                    ucfirst
                }@tags;

        $sql .= ")";
    }

    if ( @subject ) {
        $sql .= " AND (";

        $sql .= join " OR ",
                map {
                    "subject LIKE '%$_%'"
                } @subject;

        $sql .= ")";
    }

    my $rows = $dbh->selectall_arrayref( $sql );

    return map {
            $_->[0]
        } @$rows;
}

sub get_message {
    my ( $mail_id ) = @_;

    $response = $inbox->read_message( $mail_id );

    save_to_db();

    check_rpc_limit()
        or return;

    return 1;
}

sub save_to_db {
    my $insert_sth = $dbh->prepare_cached( <<SQL
INSERT OR REPLACE INTO mail_message
( id, body,
  image_url, image_title, image_link,
  link_url, link_label,
  map_surface,
  recipients_json, table_json, map_buildings_json )
VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
SQL
    );

    my $mail = $response->{message};

    my @bind = @{$mail}{qw( id body )};

    push @bind, $mail->{attachments}{image} ? @{ $mail->{attachments}{image} }{qw( url title link )}
                :                             ( undef, undef, undef );

    push @bind, $mail->{attachments}{link} ? @{ $mail->{attachments}{link} }{qw( url label )}
                :                            ( undef, undef );

    push @bind, $mail->{attachments}{map} ? @{ $mail->{attachments}{map} }{'surface'}
                :                             ( undef );

    push @bind, $json->Dump( $mail->{recipients} );

    push @bind, $mail->{attachments}{table} ? $json->Dump( $mail->{attachments}{table} )
                :                             undef;

    push @bind, $mail->{attachments}{map} ? $json->Dump( $mail->{attachments}{map}{buildings} )
                :                           undef;

    if ( $opts{debug} ) {
        warn "DEBUG:     Inserting message: $mail->{id}\n";
    }

    $insert_sth->execute(
        @bind,
    );

    if ( $mail->{has_archive} ) {
        # update index
        my $index_sth = $dbh->prepare_cached(
            "UPDATE mail_index SET has_archived = 1 WHERE id = ?"
        );
        $index_sth->execute( $mail->{id} );
    }
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
    --max-messages X # Defaults to 1000 - consider daily RPC limit
    --max-rpc X      # Defaults to 4500 - will not continue if the RPC count
                     # returned by the server exceeds this number
    --dbfile PATH    # Defaults to mail.db in the current directory
    --help           # Print help message and exit
    --debug          # Print verbose diagnostics
    --dryrun         # Only print out how many messages would be downloaded
                     # with the provided arguments.
    --ok             # If neither --subject of any of the below `tags`
                     # options are given, you must provide --ok to force it
                     # to download mail

    --subject X      # Download only messages matching the given string,
                     # and number of --subject options may be provided

    # To restrict the downloads to only messages with certain tags,
    # you may provide any of the following 5 options
    --tutorial
    --correspondence
    --medal
    --intelligence
    --alert

Download message bodies.

Message headers must already have been downloaded with `mail-index.pl`.
Regardless of the options given, this will not download a message whose body
is already saved in the database.

END_USAGE

}
