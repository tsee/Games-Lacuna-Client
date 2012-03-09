package Games::Lacuna::Client::Captcha;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Browser::Open qw( open_browser );
use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
our @ISA = qw(Games::Lacuna::Client::Module);

use Class::XSAccessor {
    getters => [qw(guid url)],
};

sub api_methods {
    return {
        fetch => { default_args => [qw(session_id)] },
        solve => { default_args => [qw(session_id guid)] },
    };
}

sub new {
    my $class = shift;
    my %opt = @_;
    my $self = $class->SUPER::new(@_);
    bless $self => $class;
    return $self;
}

sub fetch {
    my $self = shift;
    my $result = $self->_fetch(@_);
    $self->{guid} = $result->{guid};
    return $result;
}

sub open_in_browser {
    my $self = shift;
    my $result = $self->fetch;
    my $ok = open_browser( $result->{url} );
    return 1 if defined $ok && $ok == 0;
    
    return;
}

sub print_url {
    my $self = shift;
    my $result = $self->fetch;
    print "URL: $result->{url}\n";
}

sub prompt_for_solution {
    my $self = shift;
    print "Answer? ";
    my $answer = <STDIN>;
    chomp($answer);
    return $answer;
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Captcha - The captcha module

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

<<<<<<< HEAD
Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller
=======
Dave Olszewski, E<lt>cxreg@pobox.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Dave Olszewski
>>>>>>> ea148822286db6eb223c2e51da39d78c82328454

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
