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

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use MIME::Lite;
use YAML::Any (qw(LoadFile DumpFile));
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
}

my $email_file = shift(@ARGV) || 'forward_email.yml';
unless ( $email_file and -e $email_file ) {
    die "Did not provide a forward_email config file";
}

my $email_conf = LoadFile($email_file);

my $client = Games::Lacuna::Client->new(
    cfg_file => $cfg_file,
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

# Check messages
for my $message ( reverse @{ $inbox->{messages} } ) {
    
    next if $message->{id} <= $last_seen_id;
    
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

