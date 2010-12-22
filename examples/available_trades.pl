#!/usr/bin/perl 
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptions);

use Data::Dumper;
use Games::Lacuna::Client;
use Games::Lacuna::Client::PrettyPrint;
use Games::Lacuna::Client::Types ':list';
use List::MoreUtils qw(any);

$| = 1;

my $show_usage = 0;
my $show_color = 0;
my $use_sst = 0;
my $planet = '';
my @filters = ();
my @sorts = ();
my $sort_descending = 0;
my $max_pages = 20;

GetOptions(
    'help'      => \$show_usage,
    'sst'       => \$use_sst,
    'color'     => \$show_color,
    'planet=s'  => \$planet,
    'filter=s'  => \@filters,
    'sort=s'    => \@sorts,
    'desc'      => \$sort_descending,
    'max-pages=n' => \$max_pages
);

print << '__END_USAGE__' if $show_usage;
Usage:  perl available_trades.pl [options]
    
This script will pull the list of available trades from a trade ministry or
subspace transporter, optionally filter and sort it, and present it in a
single list, optionally with ANSI color-coding.

WARNING: This trade will make up to --max_pages requests for available trades,
running it repeatedly could be expensive in terms of RPC calls.

Valid options:
  --help           Show this usage message.
  --max-pages <n>  Pull at most <n> pages from the building.  Default=20.
  --color          Show ANSI colors.
  --sst            Show trades at the subspace transporter rather than 
                   the trade ministry (trade ministry is default).
  --planet         specify the planet (by name) to use for the listing.
                   If not specified, the script scans your empire for
                   a planet with a suitable building.
  --sort <key>     Sort the trade listing by the given key, one of:*
                   offer_quantity,offer_description,offer_type,real_type**,
                   ratio**,ask_quantity,ask_description,ask_type.  You may
                   specify this order more than once, and the sorts are
                   applied in the order specified.
  --desc           Specify a descending, rather than ascending, sort.
  --filter <str>   Specify a filter, showing only items which match.
                   You may specify as many filters as you like, all will
                   apply.  Filters are comprised of a key, a comparator, 
                   and a value.
                   Valid comparators are =,==,>=,>,<, and <= for 
                   ask_quantity and offer_quantity. For other keys,
                   only = or == (which are equivalent) are allowed.
                   If using > or < in your comparator, take care to 
                   quote your argument to avoid shell interpretation.

Example filter options:
  --filter 'ask_quantity<50' --filter ask_type=essentia
     Show only trades asking for less than 50 essentia

  --filter real_type=glyph       
    Show only trades offering glyphs

  --filter 'offer_quantity>=50000' --filter offer_type=energy
    Show only trades offering 50000 or more energy

 * You may technically specify any key present on the hash returned by the API,
   but sorting behavior will likely be useless on keys not listed here.
** 'real_type' is a convenience key added by this script to further qualify the
   type of offers (only for offer_type, not ask_type) by providing the following
   shorthand types:  food, ore, glyph, plan, ship.  For other types, the
   real_type is equal to the literal offer_type.
** 'ratio' is another conventience key added by this script.  The ratio is offered
   to asking quantity.  If viewing SST trades, the 1 essentia SST cost of making a 
   trade is included in the ratio calculation.
__END_USAGE__
exit(0) if $show_usage;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
	die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

$Games::Lacuna::Client::PrettyPrint::ansi_color = $show_color;
my $data = $client->empire->view_species_stats();

my $building_url = $use_sst ? '/transporter' : '/trade';

my $bid;
for my $pid (keys %{$data->{status}->{empire}->{planets}}) {
    next if ($planet ne '' && $data->{status}->{empire}->{planets}->{$pid} ne $planet);
    my $buildings = $client->body(id => $pid)->get_buildings()->{buildings};
    ($bid) = grep { $buildings->{$_}->{url} eq $building_url } keys %$buildings;
    last if defined $bid
}

if (not defined $bid) {
    if ($planet eq '') {
        die "Unable to find an appropriate building for obtaining the list on any planet.";
    } else {
        die "Unable to find an appropriate building for obtaining the list planet '$planet'.";
    }
}

my $bldg = $client->building( id => $bid, type => $use_sst ? 'Transporter' : 'Trade');

my $page_num = 1;
my $trades_per_page = 25;
my $trade_count;
my @trades;
print "Retrieving Trades";
while ($page_num <= $max_pages and (not defined $trade_count 
 or $trade_count > ($page_num * $trades_per_page ))) {
    print ".";
    my $result = $bldg->view_available_trades($page_num);
    $page_num++;
    $trade_count = $result->{trade_count};
    push @trades, @{$result->{trades}};
}
print "\n";

for (@trades) {
    $_->{ratio} = ($_->{offer_quantity} / ($_->{ask_quantity} + ($use_sst ? 1 : 0)));
    $_->{real_type} = real_type($_);

    if ($_->{ratio} < 100) {
        $_->{ratio} = sprintf("%0.4f",$_->{ratio});
    } 
    else {
        $_->{ratio} = int($_->{ratio});
    }
}

@trades = grep { filter_trade($_,@filters) } @trades;


@trades = sort {
    for my $s (@sorts) {
        my $result = $s =~ m/ratio|quantity$/ ? ($a->{$s} <=> $b->{$s}) : ($a->{$s} cmp $b->{$s});
        return $result if $result != 0;
    }
    return 0;
} @trades;

@trades = reverse @trades if $sort_descending;

Games::Lacuna::Client::PrettyPrint::trade_list(@trades);

sub filter_trade {
    my ($trade, @filters) = @_;
    for my $f (@filters) {
        my ($key,$cmp,$val) = $f =~ /(.+)(=|==|<=|<|>=|>)(.+)/;
        if (any { not defined $_ } ($key,$cmp,$val) ) {
            warn "Unnable to parse filter: $f";
            next;
        }
        my $trade_val = $trade->{$key};
        if ($key eq 'ask_quantity' or $key eq 'offer_quantity') {
            my $result = eval "$trade_val $cmp $val";
            return 0 if not $result;
        } 
        elsif ($cmp ne '=' and $cmp ne '==') {
            warn "Only equality (= or ==) permitted to filter strings: $f";
            next;
        }
        else {
            return 0 if not (lc($trade_val) eq lc($val)); # Case-insensitive
        }
    }
    return 1;
}

sub real_type {
    my ($offer) = @_;

    my ($type, $description) = @{$offer}{qw(offer_type offer_description)};

    if (any { $_ eq $type } food_types()) {
        return 'food';
    } 
    elsif (any { $_ eq $type } ore_types()) {
        if ($type eq $description) {
            return 'glyph';
        } else {
            return 'ore';
        }
    }
    elsif ($type eq 'prisoner') {
        return 'prisoner';
    }
    elsif ($description =~ m/(.*)\s*\(/) {
        if ($description =~ /Level/) {
            return 'plan';
        } else {
            return 'ship';
        }
    }
    else {
        return $type;
    }
}
