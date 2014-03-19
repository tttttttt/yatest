#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Memcached::Client2;

my $h = Memcached::Client2->new;
$h->connect;
=cut
my $a1 = $h->add('key' => 'test_key1', 'value' => 'test_value1', 'expires' => 0, 'flags' => 0);
print(Dumper($a1));

my $a2 = $h->add('key' => 'test_key2', 'value' => 'test_value2', 'expires' => 0, 'flags' => 0);
print(Dumper($a2));

my $a3 = $h->add('key' => 'test_key3', 'value' => 'test_value3', 'expires' => 0, 'flags' => 0, 'noreply' => 1);
print(Dumper($a3));
=cut
my $s1 = $h->set('key' => 'set_test_key1', 'value' => 100, 'expires' => 0, 'flags' => 0);
print(Dumper($s1));

my $s2 = $h->set('key' => 'set_test_key2', 'value' => 75, 'expires' => 0, 'flags' => 0);
print(Dumper($s2));

my $i1 = $h->incr('key' => 'set_test_key1', 'value' => 100);
print(Dumper($i1));

my $d1 = $h->decr('key' => 'set_test_key2', 'value' => 50);
print(Dumper($d1));

my $ig1 = $h->get('key' => 'set_test_key1');
print(Dumper($ig1));

my $dg1 = $h->get('key' => 'set_test_key2');
print(Dumper($dg1));

my $mg1 = $h->get('key' => ['set_test_key1', 'set_test_key2', 'rrr', 'xxx']);
print(Dumper($mg1));

=cut

my $r1 = $h->replace('key' => 'test_key3', 'value' => 'test_value3', 'expires' => 0, 'flags' => 0);
print(Dumper($r1));

my $r2 = $h->replace('key' => 'test_key3', 'value' => 'test_value3', 'expires' => 0, 'flags' => 0, 'noreply' => 1);
print(Dumper($r2));

my $g1 = $h->get('key' => 'test_key1');
print(Dumper($g1));

my $g2 = $h->get('key' => 'test_key2');
print(Dumper($g2));

my $g3 = $h->get('key' => ['test_key1', 'test_key2']);
print(Dumper($g3));
=cut

my $stats = $h->stats;
print(Dumper($stats));
