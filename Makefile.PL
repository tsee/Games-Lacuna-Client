
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'An RPC client for the Lacuna Expanse',
  'AUTHOR' => 'Steffen Mueller <smueller@cpan.org>, Gavin Mogan <halkeye@cpan.org>',
  'BUILD_REQUIRES' => {},
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.30'
  },
  'DISTNAME' => 'Games-Lacuna-Client',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'Games::Lacuna::Client',
  'PREREQ_PM' => {
    'AnyEvent' => '0',
    'Class::MOP' => '0',
    'Class::XSAccessor' => '1.07',
    'Crypt::SSLeay' => '0',
    'Data::Dumper' => '0',
    'Date::Format' => '0',
    'Date::Parse' => '0',
    'DateTime' => '0',
    'Exception::Class' => '0',
    'FindBin' => '0',
    'HTTP::Request' => '0',
    'HTTP::Response' => '0',
    'IO::Interactive' => '0',
    'JSON::RPC::Common' => '0',
    'JSON::RPC::LWP' => '0.006',
    'LWP::UserAgent' => '0',
    'MIME::Lite' => '0',
    'Moose' => '0',
    'Number::Format' => '0',
    'Scalar::Util' => '0',
    'Time::HiRes' => '0',
    'Try::Tiny' => '0.07',
    'URI' => '0',
    'YAML::Any' => '0',
    'namespace::clean' => '0.20'
  },
  'VERSION' => '0.002',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



