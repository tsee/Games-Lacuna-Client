use 5.008000;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Games::Lacuna::Client',
    VERSION_FROM => 'lib/Games/Lacuna/Client.pm',    # finds $VERSION
    PREREQ_PM    => {
        'JSON::RPC::Common' => '0',
        'HTTP::Request'     => '0',
        'HTTP::Response'    => '0',
        'LWP::UserAgent'    => '0',
        'Data::Dumper'      => '0',
        'Class::XSAccessor' => '1.07',
        'Scalar::Util'      => '0',
        'URI'               => '0',
        'Class::MOP'        => '0',
        'YAML::Any'         => '0',
        'AnyEvent'          => '0',
        'Date::Parse'       => '0',
        'Date::Format'      => '0',
        'Number::Format'    => '0',
        'FindBin'           => '0',
        'MIME::Lite'        => '0',
        'Crypt::SSLeay'     => '0', # or IO::Socket::SSL
        'Exception::Class'  => '0',
    },                                               # e.g., Module::Name => 1.1
    (
        $] >= 5.005
        ?    ## Add these new keywords supported since 5.005
          (
            ABSTRACT_FROM =>
              'lib/Games/Lacuna/Client.pm',    # retrieve abstract from module
            AUTHOR => 'Steffen Mueller <smueller@cpan.org>'
          )
        : ()
    ),
);
