package Memcached::Client2::Util;

use strict;
use warnings;
use Data::Dumper;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/
    validate_params
    parse_complex_response
    parse_complex_response2
    %all_cmds
    %cas_cmds
    %storage_cmds
    %retrieval_cmds
    %deletion_cmds
    %incr_decr_cmds
    %touch_cmds
    %stats_cmds
/;

use constant MAX_KEY_LENGTH => 250;

our %cas_cmds = (
    'cas' => 1,
);

our %storage_cmds = (
    'add' => 1,
    'append' => 1,
    'prepend' => 1,
    'replace' => 1,
    'set' => 1,
    %cas_cmds,
);

our %retrieval_cmds = (
    'get' => 1,
    'gets' => 1,
);

our %deletion_cmds = (
    'delete' => 1,
);

our %incr_decr_cmds = (
    'decr' => 1,
    'incr' => 1,
);

our %touch_cmds = (
    'touch' => 1,
);

our %stats_cmds = (
    'stats' => 1,
);

our %all_cmds = (
    %storage_cmds,
    %retrieval_cmds,
    %deletion_cmds,
    %incr_decr_cmds,
    %touch_cmds,
    %stats_cmds,
);

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

sub parse_complex_response {
    my ($method, $data, $multi, $from_str) = @_;

    my $crlf;

    if($from_str) {
        $crlf = '';
    } else {
        $crlf = "\r\n";
    }

    if($retrieval_cmds{$method}) {
        if($from_str && !$multi) {
            return $data->[0];
        } else {
            my (@values, $fetch_next);
            foreach my $row (@$data) {
                if($row =~ m/^VALUE (?:.+)$crlf/) {
                    $fetch_next = 1;
                    next;
                } else {
                    if($fetch_next) {
                        $row =~ m/^(.+)$crlf/;
                        push(@values, $1);
                        $fetch_next = 0;
                    }
                }
            }
    
            return $multi ? \@values : $values[0];
        }
    } elsif($stats_cmds{$method}) {
        my @stats;

        foreach my $row (@$data) {
            if($row =~ m/^STAT (.+)$/) {
                push(@stats, $1);
            }
        }

        return \@stats;
    }
}

sub parse_complex_response2 {
    my ($method, $data, $multi) = @_;

    my @data = split(/\r\n/, $data);

    return parse_complex_response($method, \@data, $multi, 1);
}

1;
