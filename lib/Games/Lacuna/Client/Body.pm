package Games::Lacuna::Client::Body;
use 5.0080000;
use strict;
use warnings;

use Moose;
extends qw(Games::Lacuna::Client::Module);

has body_id => (
  is => 'ro',
  isa => 'Int',
  init_arg => 'id',
);

sub api_methods {
  return {
    get_buildings => { default_args => [qw(session_id body_id)] },
    get_status    => { default_args => [qw(session_id body_id)] },
    get_buildable => { default_args => [qw(session_id body_id)] },
    rename        => { default_args => [qw(session_id body_id)] },
    abandon       => { default_args => [qw(session_id body_id)] },
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;
__PACKAGE__->init();
1;
__END__

=head1 NAME

Games::Lacuna::Client::Body - The body module

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
