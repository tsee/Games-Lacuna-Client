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

my $client = Games::Lacuna::Client->new(
    cfg_file  => $cfg_file,
    rpc_sleep => 2,
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

my $archive_match = $email_conf->{archive} || [];
my $trash_match   = $email_conf->{trash}   || [];

# Load Inbox
my $inbox = $client->inbox->view_inbox;

exit if !$inbox->{message_count};

# Last seen message
my $cache_file_path = File::Spec->catfile(
    $email_conf->{cache_dir},
    'forward_email.yml'
);

my $cache = -e $cache_file_path ? LoadFile($cache_file_path)
          :                       {};

my $last_seen_id = $cache->{last_seen_id} || 0;
my @archive_id;
my @trash_id;

# Check messages
MESSAGE:
for my $message ( reverse @{ $inbox->{messages} } ) {
    
    next if $message->{id} <= $last_seen_id;
    
    for my $regex ( @$archive_match ) {
        if ( $message->{subject}  =~ m/$regex/i ) {
            push @archive_id, $message->{id};
            next MESSAGE;
        }
    }
    
    for my $regex ( @$trash_match ) {
        if ( $message->{subject} =~ m/$regex/i ) {
            push @trash_id, $message->{id};
            next MESSAGE;
        }
    }
    
    next if $message->{has_read};
    
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
    
    $last_seen_id = $message->{id};
}

# Update cache
$cache->{last_seen_id} = $last_seen_id;

DumpFile( $cache_file_path, $cache );

# archive messages
if ( @archive_id ) {
    $client->inbox->archive_messages(
        \@archive_id,
    );
}

# delete messages
if ( @trash_id ) {
    $client->inbox->trash_messages(
        \@trash_id,
    );
}

# announcements
if (   $email_conf->{forward_announcements}
    && $inbox->{status}{server}{announcement} )
{
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

