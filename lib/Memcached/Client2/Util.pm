package Memcached::Client2::Util;

use strict;
use warnings;
use Data::Dumper;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/validate_params/;

use constant MAX_KEY_LENGTH => 250;

my %validators = (
    'key' => \&validate_key,
    'expires' => \&validate_expires,
    'flags' => \&validate_flags,
);

sub validate_params {
    my ($method, $params) = @_;

    foreach my $key (keys(%$params)) {
        if($validators{$key}) {
            $validators{$key}->($params->{$key});
        }
    }
}

sub validate_key {
    my ($key) = @_;

    my @keys;

    if(ref($key) eq 'ARRAY') {
        @keys = @$key;
    } else {
        @keys = ($key);
    }

    foreach my $k (@keys) {
        die('key is empty') if(!$k);
        die('key includes control character(s)') if($k =~ m/[[:cntrl:]]/);
        die('key includes whitespace(s)') if($k =~ m/[[:space:]]/);
        die('key is too long') if(length($k) > MAX_KEY_LENGTH);
    }
}

sub validate_expires {
    my ($expires) = @_;

    die('expires is empty') if(!defined($expires) || $expires eq '');
    die('expires has invalid value') if($expires !~ m/\d+/);
}

sub validate_flags {
    my ($flags) = @_;

    die('flags is empty') if(!defined($flags) || $flags eq '');
    die('flags has invalid value') if($flags !~ m/\d+/);
}

1;
