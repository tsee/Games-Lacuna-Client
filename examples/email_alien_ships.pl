#!/home/cafranks/perl5/perlbrew/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            ();
use List::MoreUtils       qw( none );
use MIME::Lite            ();
use YAML::Any             (qw(DumpFile LoadFile));
use Games::Lacuna::Client ();

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $email_file = shift(@ARGV) || 'email_alien_ships.yml';
unless ( $email_file and -e $email_file ) {
    die "Did not provide an email_alien_ships config file";
}

my $email_conf = LoadFile($email_file);

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);
$email_conf->{cache_dir} ||= $client->cache_dir;

# validate config file
for my $key (qw(cache_dir email)) {
    die "key '$key' missing from forward_email config file"
        if !$email_conf->{$key};
}

die "email: 'to' key missing from forward_email config file"
    if !$email_conf->{email}{to};

# Email defaults
$email_conf->{email}{from}    ||= $email_conf->{email}{to};
$email_conf->{email}{subject} ||= 'New incoming alien ships!';

# MIME::Lite config
my $mime_lite_conf = $email_conf->{mime_lite} || [];

die "mime_lite key in forward_email config file must be a list"
    if ref($mime_lite_conf) ne 'ARRAY';

# Retreive cache of already-seen ships
my $cache_file_path = File::Spec->catfile(
    $email_conf->{cache_dir},
    'email_alien_ships.yml'
);

my $cache = -e $cache_file_path ? LoadFile($cache_file_path)
          :                       {};

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my @incoming;

# Scan each planet
foreach my $name ( sort keys %planets ) {

    next if $email_conf->{planets} && none { lc $name eq lc $_ } @{ $email_conf->{planets} };

    # Load planet data
    my $planet    = $client->body( id => $planets{$name} );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};

    next unless $body->{incoming_foreign_ships};

    my $buildings = $result->{buildings};

    # Find the Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;
    next unless $space_port_id;

    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );

    my @new_ships;

    for (my $pageNum = 1; ; $pageNum++)
    {
        my $ships = $space_port->view_foreign_ships($pageNum)->{ships};

        for my $ship (@$ships) {
            # only keep ships not from our own empire
            next if $ship->{from}{empire}{id} && $ship->{from}{empire}{id} == $empire->{id};

            # check cache
            next if grep {
                   $_->{id} == $ship->{id}
                && $_->{date_arrives} eq $ship->{date_arrives}
            } @{ $cache->{$name} };

            push @new_ships, $ship;
        }
        last if scalar @$ships != 25;
    }

    push @incoming, {
        name  => $name,
        ships => \@new_ships,
    } if @new_ships;
}

exit if !@incoming;

# Send email
my $body = '';

for my $planet (@incoming) {
    $body .= sprintf "%s\n", $planet->{name};
    $body .= "=" x length $planet->{name};
    $body .= "\n";

    my %count;
    map { $count{ $_->{type_human} } ++ }
        @{ $planet->{ships} };

    for my $type ( keys %count ) {
        $body .= sprintf "%s: %d\n", $type, $count{$type};
    }
    $body .= "\n";

    for my $ship (@{ $planet->{ships} }) {

        my $type = $ship->{type_human} ? $ship->{type_human}
                 :                       'Unknown ship';

        my $from = $ship->{from}{name} ? sprintf( "%s [%s]",
                                            $ship->{from}{name},
                                            $ship->{from}{empire}{name} )
                 :                       'Unknown location';

        my $when = $ship->{date_arrives};

        $body .= <<OUTPUT;
$type from $from
Arriving $when

OUTPUT
    }
}

my $email = MIME::Lite->new(
    From    => $email_conf->{email}{from},
    To      => $email_conf->{email}{to},
    Subject => $email_conf->{email}{subject},
    Type    => 'TEXT',
    Data    => $body,
);

$email->send( @$mime_lite_conf );

# Update cache
for my $planet (@incoming) {
    for my $ship ( @{ $planet->{ships} } ) {
        push @{ $cache->{ $planet->{name} } },
            {
                id           => $ship->{id},
                date_arrives => $ship->{date_arrives},
            };
    }
}

DumpFile( $cache_file_path, $cache );
