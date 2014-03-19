#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Memcached::Client2;

my $h = Memcached::Client2->new;
$h->connect;

#ok($h->add('key' => 'test_key1', 'value' => 'test_value1', 'expires' => 0, 'flags' => 0));
#ok($h->add('key' => 'test key2', 'value' => 'test_value2', 'expires' => 0, 'flags' => 0));
ok($h->add('key' => 'test_key3', 'value' => 'test_value3', 'expires' => 0, 'flags' => 0, 'noreply' => 1));
#ok($h->get('key' => 'test_key1') eq 'test_value1');
#ok($h->get('key' => 'test_key2') eq 'test_value2');
#is_deeply($h->get('key' => ['test_key1', 'test_key2']), ['test_value1', 'test_value2'], 'multi get');

done_testing;
