package Games::Lacuna::Client::Alliance;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;

use namespace::clean;
use Moose;

extends 'Games::Lacuna::Client::Module';

has alliance_id => (
  is => 'ro',
  init_arg => 'id',
);

sub api_methods {
  return {
    find         => { default_args => [qw(session_id)] },
    view_profile => { default_args => [qw(session_id alliance_id)] },
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;
__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Alliance - The alliance module

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
