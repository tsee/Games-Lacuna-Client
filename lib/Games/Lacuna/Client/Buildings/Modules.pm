package Games::Lacuna::Client::Buildings::Modules;
use 5.0080000;
use strict;
use Carp 'croak';
use warnings;

use Games::Lacuna::Client;
use Games::Lacuna::Client::Buildings;

our @ISA = qw(Games::Lacuna::Client::Buildings);

sub build {
  croak "SpaceStation modules don't inherit a 'build' method from Buildings\n";
}

sub upgrade {
  croak "SpaceStation modules don't inherit a 'upgrade' method from Buildings\n";
}

sub downgrade {
  croak "SpaceStation modules don't inherit a 'downgrade' method from Buildings\n";
}

sub demolish {
  croak "SpaceStation modules don't inherit a 'demolish' method from Buildings\n";
}

sub repair {
  croak "SpaceStation modules don't inherit a 'repair' method from Buildings\n";
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Modules - Space Station's version of a building

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Carl Franks, E<lt>cfranks@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Carl Franks

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
