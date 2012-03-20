#!/usr/bin/perl
# A kludge for Windows people using Active State Perl
# to install all modules.
use strict;
use warnings;

  my $modules = mod_list();
  for my $mod (@$modules) {
    system("ppm", "install", "$mod");
  }
exit;

sub mod_list {
  my @list = qw(
AnyEvent
Browser::Open
Class::MOP
Class::XSAccessor
Crypt::SSLeay
Data::Dumper
Date::Format
Date::Parse
DateTime
Exception::Class
FindBin
HTTP::Request
HTTP::Response
IO::Interactive
JSON::RPC::Common
JSON::RPC::LWP
LWP::UserAgent
Math::Round
MIME::Lite
Moose
Number::Format
Scalar::Util
Time::HiRes
Try::Tiny
URI
YAML::Any
namespace::clean
);

  return \@list;
}
