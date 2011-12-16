package Games::Lacuna::Client::Stats;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
our @ISA = qw(Games::Lacuna::Client::Module);

sub api_methods {
  return {
    credits => { default_args => [] },
    (
      map {
        ($_ => { default_args => [qw(session_id)] })
      }
      qw(
        alliance_rank
        find_alliance_rank
        empire_rank
        find_empire_rank
        colony_rank
        spy_rank
        weekly_medal_winners
      )
    ),
  };
}

#sub new {
#  my $class = shift;
#  my %opt = @_;
#  my $self = $class->SUPER::new(@_);
#  bless $self => $class;
#  $self->{body_id} = $opt{id};
#  return $self;
#}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Stats - The server stats module

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
