package Games::Lacuna::Client::Buildings;
use 5.010000;
use strict;
use warnings;
use Scalar::Util 'weaken';
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
our @ISA = qw(Games::Lacuna::Client::Module);

use Class::XSAccessor {
  getters => [qw(building_id)],
};

sub api_methods {
  return {
    build               => { default_args => [qw(session_id)] },
    view                => { default_args => [qw(session_id building_id)] },
    upgrade             => { default_args => [qw(session_id building_id)] },
    demolish            => { default_args => [qw(session_id building_id)] },
    downgrade           => { default_args => [qw(session_id building_id)] },
    get_stats_for_level => { default_args => [qw(session_id building_id)] },
    repair              => { default_args => [qw(session_id building_id)] },
  };
}

sub new {
  my $class = shift;
  my %opt = @_;
  my $self = $class->SUPER::new(@_);
  $self->{building_id} = $opt{id};
  # We could easily support the body_id as default argument for ->build
  # here, but that would mean you had to specify the body_id at build time
  # or require building construction via $body->building(...)
  # Let's keep it simple for now.
  #$self->{body_id} = $opt{body_id};
  return $self;
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings - The buildings module

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
