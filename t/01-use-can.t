#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('Memcached::Client2');
}

my $c = Memcached::Client2->new;

can_ok($c, qw/close add append prepend replace set cas get gets delete incr decr touch stats/);

done_testing;
