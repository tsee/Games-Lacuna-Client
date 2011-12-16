#!/usr/bin/perl

# usage:
# > forward_email.pl /path/to/lacuna.yml /path/to/forward_email.yml
#
# ARG1 defaults to 'lacuna.yml' in the current directory
# ARG2 defaults to 'forward_email.yml' in the current directory
#
# forward_email.yml must describe a YAML mapping
#
# The 'cache_dir' key/value is required
# The 'email' key/value is required, and must describe a mapping containing
# a 'to' key/value. If a 'from' key/value is not supplied, it defaults to
# the 'from' value.
# A 'mime_lite' key/value is optional. If present, it must describe a sequence
# of scalar values to be passed directly to the MIME::Lite send() method
# If you do not provide any 'mime_lite' values, it will default to using
# the local `sendmail` program
#
# You can provide 'archive' and 'trash' lists - these are matched against all
# mails (whether read or not) as a case-insensitive regex, and the email is
# archived or trashed if the subject line matches.
# Matching emails are never forwarded to your email.
#
# This only forwards the short 'body_preview' from the inbox listing
# this ensures all mail is left flagged as unread.
#
# If max_pages is set, the last-seen-id will not be cached, otherwise if there
# are many messaged not being archived/trashed, we could end up with pages
# never being processed.
#
# example forward_email.yml

#cache_dir: '/path/to/cache/dir/which/must/be/writeable'
#
#email:
#    to: 'me@example.com'
#    from: 'you@example.com'
#
#mime_lite:
#    - smtp
#    - 'smtp.example.com'
#
#max_pages: 2
#
#archive:
#    - '^Probe Detected!$'
#
#trash:
#    - '^Glyph Discovered!$'

use strict;
use warnings;
use File::Spec;
use LWP::UserAgent;
use MIME::Lite;
use URI;
use YAML::Any (qw(LoadFile DumpFile));

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();

# All servers so far have used this same value
my $messages_per_page = 25;

my $DEBUG = 0;

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

my $email_file = shift(@ARGV) || 'forward_email.yml';
unless ( $email_file and -e $email_file ) {
    die "Did not provide a forward_email config file";
}

my $email_conf = LoadFile($email_file);

debug( { conf => $email_conf } );

my $client = Games::Lacuna::Client->new(
    cfg_file  => $cfg_file,
    rpc_sleep => 3,
    # debug    => 1,
);

# validate config file
for my $key (qw(cache_dir email)) {
    die "key '$key' missing from forward_email config file"
        if !$email_conf->{$key};
}

die "email: 'to' key missing from forward_email config file"
    if !$email_conf->{email}{to};

# Email defaults
$email_conf->{email}{from} ||= $email_conf->{email}{to};

# MIME::Lite config
my $mime_lite_conf = $email_conf->{mime_lite} || [];

die "mime_lite key in forward_email config file must be a list"
    if ref($mime_lite_conf) ne 'ARRAY';

my $max_pages     = $email_conf->{max_pages} || 0;
my $archive_match = $email_conf->{archive}   || [];
my $trash_match   = $email_conf->{trash}     || [];

# Last seen message
my $cache_file_path = File::Spec->catfile(
    $email_conf->{cache_dir},
    'forward_email.yml'
);

debug( $cache_file_path );

my $cache = -e $cache_file_path ? LoadFile($cache_file_path)
          :                       {};

debug( { cache => $cache } );

my $last_seen_id = $cache->{last_seen_id} || 0;

# Keep fetching pages until we see a message we've already processed
my $page = 1;
my @messages;
my $server_announcement;

PAGE:
while (1) {
    debug( "Fetching Inbox page $page" );

    my $response = $client->inbox->view_inbox( { page_number => $page } );

    $server_announcement ||= $response->{status}{server}{announcement};

    for my $message ( @{ $response->{messages} } ) {
        if ( $message->{id} <= $last_seen_id ) {
            debug( "Already seen this message - don't fetch any more" );
            last PAGE;
        }

        push @messages, $message;
    }

    if ( $max_pages && $page >= $max_pages ) {
        debug("Fetched max-pages '$max_pages' - don't fetch any more");
        last PAGE;
    }
    if ( $response->{message_count}  > ( $messages_per_page * $page ) ) {
        $page++;
    }
    else {
        last PAGE;
    }
}

debug( sprintf "Fetched %d messages", scalar @messages );

# Check messages
my @archive_id;
my @trash_id;

MESSAGE:
for my $message ( reverse @messages ) {

    if ( !$max_pages && $message->{id} > $last_seen_id ) {
        $last_seen_id = $message->{id};
    }

    for my $regex ( @$archive_match ) {
        if ( $message->{subject}  =~ m/$regex/i ) {
            debug(
                sprintf "Message '%s' matched archive regex '%s'",
                    $message->{subject},
                    $regex,
            );

            push @archive_id, $message->{id};
            next MESSAGE;
        }
    }

    for my $regex ( @$trash_match ) {
        if ( $message->{subject} =~ m/$regex/i ) {
            debug(
                sprintf "Message '%s' matched trash regex '%s'",
                    $message->{subject},
                    $regex,
            );

            push @trash_id, $message->{id};
            next MESSAGE;
        }
    }

    if ( $message->{has_read} ) {
        debug( sprintf "Skipping read message: '%s'", $message->{subject} );
        next;
    }

    my $body = <<BODY;
$message->{date}
From: $message->{from}
$message->{body_preview}

BODY

    my $email = MIME::Lite->new(
        From    => $email_conf->{email}{from},
        To      => $email_conf->{email}{to},
        Subject => $message->{subject},
        Type    => 'TEXT',
        Data    => $body,
    );

    $email->send( @$mime_lite_conf );

    debug( sprintf "Forwarded message: '%s'", $message->{subject} );
}

debug( "last-seen-id is now: '$last_seen_id'" );


# Update cache
$cache->{last_seen_id} = $last_seen_id;

DumpFile( $cache_file_path, $cache );

# archive messages
if ( @archive_id ) {
    $client->inbox->archive_messages(
        \@archive_id,
    );

    debug( sprintf "Archived %d messages", scalar @archive_id );
}

# delete messages
if ( @trash_id ) {
    $client->inbox->trash_messages(
        \@trash_id,
    );

    debug( sprintf "Trashed %d messages", scalar @trash_id );
}

# announcements
if ( $email_conf->{forward_announcements} && $server_announcement ) {

    debug( "Forwarding server announcement" );

    my $url = URI->new( $client->uri );
    $url->path('announcement');
    $url->query_form( session_id => $client->session_id );

    my $ua = LWP::UserAgent->new;

    my $response = $ua->get($url);

    my $email = MIME::Lite->new(
        From    => $email_conf->{email}{from},
        To      => $email_conf->{email}{to},
        Subject => "Server Announcement",
        Type    => "text/html",
        Data    => $response->content,
    );

    $email->send( @$mime_lite_conf );
}


sub debug {
    return if !$DEBUG;

    for (@_) {
        if ( ref $_ ) {
            require Data::Dumper;
            print Data::Dumper::Dumper( $_ );
        }
        else {
            print "$_\n";
        }
    }
}
