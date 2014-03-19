use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    'AUTHOR'       => 'Marat Kanzafarov, marat.kanzafarov@gmail.com',
    'NAME'         => 'Memcached::Client2',
    'VERSION_FROM' => 'lib/Memcached/Client2.pm',

    'DISTNAME' => 'Memcached-Client2',
    'EXE_FILES' => [],

    'BUILD_REQUIRES' => {
        'Test::More' => '0',
    },

    'PREREQ_PM' => {
        'Data::Dumper' => '0',
        'Exporter' => '0',
        'IO::Socket::INET' => '0',
    },

    'test' => {
        'TESTS' => 't/*.t'
    },
);
