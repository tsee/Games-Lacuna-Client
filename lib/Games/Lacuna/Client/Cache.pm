package Games::Lacuna::Client::Cache;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';
use Storable ();
use File::Temp qw( tempfile );

use Class::XSAccessor {
  accessors => [qw( filename cache )],
};

sub new {
  my $class = shift;
  my $self = bless { @_ }, $class;
  $self->cache({});
  $self->load() if $self->filename();
  return $self;
}

sub _key { return join "\x0", @{$_[0]} }

sub retrieve {
  my ($self, $uri, $method_name, $params) = @_;
  my $cache = $self->cache();
  my $key = _key($params);
  return unless exists $cache->{$uri}{$method_name}{$key};
  my $retval = $cache->{$uri}{$method_name}{$key};
  $retval->{result}{cache}{age} = time() - $retval->{result}{cache}{time};
  return $retval;
}

sub store {
  my ($self, $value, $uri, $method_name, $params) = @_;
  $value = Storable::dclone($value);
  $value->{result}{cache}{time} = time();
  $self->cache()->{$uri}{$method_name}{_key($params)} = $value;
  return $self;
}

sub load {
  my $self = shift;
  $self->filename(shift) if @_;
  my $filename = $self->filename()
    or croak "no filename to load cache from";
  $self->cache(Storable::retrieve($filename)) if -e $filename;
  return $self;
}

sub save {
  my $self = shift;
  $self->filename(shift) if @_;
  my $filename = $self->filename()
    or croak "no filename to save cache to";
  my ($fh, $tmpfile) = tempfile("$filename.XXXXXXX");
  Storable::nstore_fd($self->cache(), $fh);
  close $fh or return;
  rename $tmpfile, $filename;
  return $self;
}

sub reset {
  my $self = shift;
  $self->cache({});
  return $self;
}

sub DESTROY {
  my $self = shift;
  local $Data::Dumper::Indent = 1;
  $self->save() if $self->filename();
  return;
}

1;
__END__

=head1 NAME

Games::Lacuna::Client::Cache - A basic caching module

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
