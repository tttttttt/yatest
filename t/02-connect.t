#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Memcached::Client2;

my $h = Memcached::Client2->new;

isa_ok($h, 'Memcached::Client2', 'Memcached::Client2 created');
pass($h->connect);

done_testing;
