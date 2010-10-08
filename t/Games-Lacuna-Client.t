# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Games-Lacuna-Client.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('Games::Lacuna::Client') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

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


