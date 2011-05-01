package Games::Lacuna::Client::Buildings::Archaeology;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;

use namespace::clean;
use Moose;

extends 'Games::Lacuna::Client::Buildings::Simple';

sub api_methods {
  return {
    search_for_glyph    => { default_args => [qw(session_id building_id)] },
    subsidize_search    => { default_args => [qw(session_id building_id)] },
    get_glyphs          => { default_args => [qw(session_id building_id)] },
    assemble_glyphs     => { default_args => [qw(session_id building_id)] },
    get_ores_available_for_processing => { default_args => [qw(session_id building_id)] },
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;
__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Archeology - The Archeology Ministry building

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
