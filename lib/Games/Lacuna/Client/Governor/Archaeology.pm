#
#===============================================================================
#
#  DESCRIPTION:  Archaeology plugin for Governor. Automates the
#                searching of ore for glyphs.
#
#===============================================================================

package Games::Lacuna::Client::Governor::Archaeology;
use strict;
use warnings qw(FATAL all);
use Carp;
use English qw(-no_match_vars);
use Data::Dumper;

{
    use List::MoreUtils qw(any);
    use Games::Lacuna::Client::PrettyPrint qw(trace message warning action ptime phours);

    sub run {
        my $class   = shift;
        my $gov     = shift;
        my ($pid, $status, $cfg) = @{$gov->{current}}{qw(planet_id status config)};

        my ($arch) = $gov->find_buildings('Archaeology');

        if (not defined $arch) {
            warning("There is no Archaeology Ministry on ".$gov->{planet_names}->{$pid});
            return;
        }

        if ( my $time = $gov->building_details($pid,$arch->{building_id})->{work}{seconds_remaining} ){
            $gov->set_next_action_if_sooner( $time );
            warning("The Archaeology Ministry on ".$gov->{planet_names}->{$pid}." is busy.");
            return;
        }
        my %ore_avail = %{$arch->get_ores_available_for_processing->{ore}};
        my @ores = keys %ore_avail;

        if (defined $cfg->{archaeology}->{search_only}) {
            @ores = grep { my $o = $_; any { $o eq $_ } @{$cfg->{archaeology}->{search_only}} } @ores;
        }

        if (defined $cfg->{archaeology}->{do_not_search}) {
            @ores = grep { my $o = $_; not any { $o eq $_ } @{$cfg->{archaeology}->{do_not_search}} } @ores;
        }

        my $selection = $cfg->{archaeology}->{'select'} || 'most';

        my $ore;
        if ($selection eq 'most') {
            ($ore) = sort { $ore_avail{$b} <=> $ore_avail{$a} } @ores;
        }
        elsif ($selection eq 'least') {
            ($ore) = sort { $ore_avail{$a} <=> $ore_avail{$b} } @ores;
        }
        elsif ($selection eq 'random') {
            ($ore) = splice(@ores, rand(@ores), 1) 
        }
        else {
            warning("Unknown archaeology selection command: $selection");
        }

        if( not $ore ){
            warning('Unable to find a suitable ore for archaeology');
            return;
        }

        eval {
            $arch->search_for_glyph($ore);
        };
        if ($@) {
            warning("Unable to search for $ore at archaeology ministry: $@");
        } else {
            action("Searching for $ore glyph at archaeology ministry");
        }
    }

}

1;
__END__
=pod

=head1 NAME

Games::Lacuna::Client::Governor::Archaeology - A plugin for Governor that will automate searching of ore for glyphs.

=head1 SYNOPSIS

    Add 'archaeology' to the Governor configuration priorities list.

=head1 DESCRIPTION

This module examines each colony and the probes currently available (as well as in transit)
to determine what stars the available probes should be sent to. It is a fast-and-dirty first-fit
algorithm, intended merely do expand the observatory's scan in an every increasing radius.


=head2 archaeology

This heading contains sub-keys related to archaeology searches.
NOTE: archaeology must be a specified item in the priorities list for
archaeology searches to take place.

=head3 search_only

This is a list of ore types which should be exclusively searched for

=head3 do_not_search

This is a list of ore types which should be avoided in searches

=head3 select

This is how to select among candidate ores for a search.  One of 'most',
pick whichever ore we have most of (subject to above restrictions), 'least',
pick whichever we have least of (as above), or 'random', which picks one
at random, subject to above restrictions.  If not specified, the default
is 'most'.

=head1 SEE ALSO

L<Games::Lacuna::Client>, by Steffen Mueller on which this module is dependent.

L<Games::Lacuna::Client::Governor>, by Adam Bellaire of which this module is a plugin.

Of course also, the Lacuna Expanse API docs themselves at L<http://us1.lacunaexpanse.com/api>.

=head1 AUTHOR

Adam Bellaire, E<lt>bellair@ufl.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut


