use strict;
use warnings;

use Test::More tests => 5;
BEGIN { use_ok('Games::Lacuna::Client') };

#########################

eval {
	Games::Lacuna::Client->new;
};
like($@, qr/Need the following parameters: uri name password/, 'Exception without params');

# TODO test if really need those params and what if mallformed params (eg. uri) are given?

my $client = Games::Lacuna::Client->new(
    name      => 'My empire',
    password  => 'password of the empire',
    uri       => 'https://us1.lacunaexpanse.com/',
    api_key   => 'abc',
);
isa_ok($client, 'Games::Lacuna::Client');

eval {
	Games::Lacuna::Client::Empire->new;
};
like($@, qr/Need Games::Lacuna::Client/, 'needs client to create an Empire object');

my $empire = Games::Lacuna::Client::Empire->new(client => $client);
isa_ok($empire, 'Games::Lacuna::Client::Empire');

