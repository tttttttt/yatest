package Memcached::Client2;

BEGIN {
    $Memcached::Client2::VERSION = '0.01';
}

use strict;
use warnings;
use Data::Dumper;
use IO::Socket::INET;
use IO::Select;
use Memcached::Client2::Util qw /validate_params/;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/%all_cmds %cas_cmds %storage_cmds %retrieval_cmds %deletion_cmds %incr_decr_cmds %touch_cmds %stats_cmds/;

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

sub trim {
  my ($text) = @_;
  
  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  
  return $text;
}

our $AUTOLOAD;

sub can
{
    my ($self, $method) = @_;

    my $subref = $self->SUPER::can($method);
    return $subref if($subref);
    return unless(exists($all_cmds{$method}));

    return sub {
        my $self = $_[0];

        my $subref = $self->SUPER::can($method);
        goto &$subref if($subref);

        $AUTOLOAD = $method;
        goto &AUTOLOAD;
    };
}

sub AUTOLOAD {
    my ($self) = shift;

    my ($method) = $AUTOLOAD =~ m/([^:]+)$/;

    return unless $all_cmds{$method};

    my $sub = sub {
        local *__ANON__ = $AUTOLOAD;
        my $self = shift;
        $self->_cmd(@_);
    };

    return $sub->($self, $method, @_);
}

sub new {
    my ($class, %args) = @_;

    my $self = bless({}, $class);

    $self->_init(\%args);

    return $self;
}

sub _init {
    my ($self, $args) = @_;

    $self->{'params'} = {
        'host' => $args->{'host'} || '127.0.0.1',
        'port' => $args->{'port'} || 11211,
        'timeout' => $args->{'timeout'} || 180,
        'async' => $args->{'async'},
    };
}

sub connect {
    my ($self) = @_;

    $self->_connect;
}

sub _connect {
    my ($self) = @_;

    my $socket = new IO::Socket::INET(
        'PeerHost' => $self->{'params'}->{'host'},
        'PeerPort' => $self->{'params'}->{'port'},
        'Proto' => 'tcp',
        'Timeout' => $self->{'params'}->{'timeout'},
    ) or die("socket failed ($!)");

    $self->{'socket'} = $socket;
}

sub _connect_async {

}

sub close {
    my ($self) = @_;

    $self->{'socket'}->close;
}

sub DESTROY {
    my ($self) = @_;

    $self->close;
}

sub _write_request {
    my ($self, $cmd, $method) = @_;

    my $socket = $self->{'socket'};

    print({ $self->{'socket'} } $cmd->{'request'} . (defined($cmd->{'value'}) ? $cmd->{'value'} : ''));
}

sub _read_response {
    my ($self, $method, $noreply, $multi) = @_;

    my $socket = $self->{'socket'};

    my (@data, $row);

    if($noreply) {
        return 1;
    }

    $row = <$socket>;

    if($row =~ m/^(?:ERROR|CLIENT_ERROR|SERVER_ERROR)/) {
        die("error: $row");
    } else {
        push(@data, $row);
        
        if($storage_cmds{$method}) {
            if($row eq "STORED\r\n") {
                return 1;
            } else {
                return undef;
            }
        } elsif($deletion_cmds{$method}) {
            if($row eq "DELETED\r\n") {
                return 1;
            } else {
                return undef;
            }
        } elsif($incr_decr_cmds{$method}) {
            if($row eq "NOT_FOUND\r\n") {
                return undef;
            } else {
                return trim($row);
            }
        } elsif($touch_cmds{$method}) {
            if($row eq "TOUCHED\r\n") {
                return 1;
            } else {
                return undef;
            }
        } elsif($retrieval_cmds{$method}) {
            while(my $retrieval_row = <$socket>) {
                push(@data, $retrieval_row);

                if($retrieval_row eq "END\r\n") {
                    last;
                }
            }
        } elsif($stats_cmds{$method}) {
            while(my $stats_row = <$socket>) {
                push(@data, $stats_row);

                if($stats_row eq "END\r\n") {
                    last;
                }
            }
        }
    }
    
    if($retrieval_cmds{$method}) {
        my (@values, $fetch_next);
        foreach my $row (@data) {
            if($row =~ m/^VALUE (?:.+)\r\n/) {
                $fetch_next = 1;
                next;
            } else {
                if($fetch_next) {
                    $row =~ m/^(.+)\r\n/;
                    push(@values, $1);
                    $fetch_next = 0;
                }
            }
        }

        return $multi ? \@values : $values[0];
    } elsif($stats_cmds{$method}) {
        my @stats;

        foreach my $row (@data) {
            if($row =~ m/^STAT (.+)$/) {
                push(@stats, $1);
            }
        }

        return \@stats;
    }
}

sub _do_cmd {
    my ($self, $cmd, $method, $noreply, $get_multi) = @_;

    $self->_write_request($cmd, $method);
    return $self->_read_response($method, $noreply, $get_multi);
}

sub _cmd {
    my ($self, $method, %params) = @_;

    validate_params($method, \%params);
    
    my $multi;

    my $cmd = {};

    if($storage_cmds{$method}) {
        my $bytes = length($params{'value'});

        if($cas_cmds{$method}) {
            # cas <key> <flags> <exptime> <bytes> <cas unique> [noreply]\r\n
            $cmd->{'request'} = "$method $params{'key'} $params{'flags'} $params{'expires'} $bytes $params{'cas_unique'}" . ($params{'noreply'} ? ' noreply' : '');
            $cmd->{'value'} = $params{'value'};
        } else {
            # <command name> <key> <flags> <exptime> <bytes> [noreply]\r\n
            $cmd->{'request'} = "$method $params{'key'} $params{'flags'} $params{'expires'} $bytes" . ($params{'noreply'} ? ' noreply' : '');
            $cmd->{'value'} = $params{'value'};
        }
    }

    elsif($retrieval_cmds{$method}) {
        # get <key>*\r\n
        # gets <key>*\r\n

        # key может содержать несколько ключей, разделенных пробелами
        my $key;
  
        if(ref($params{'key'}) eq 'ARRAY') {
            $multi = 1;
            $key = join(' ', @{$params{'key'}});
        } else {
            $key = $params{'key'};
        }

        $cmd->{'request'} = "$method $key";
    }

    elsif($deletion_cmds{$method}) {
        # delete <key> [noreply]\r\n
  
        $cmd->{'request'} = "$method $params{'key'}" . ($params{'noreply'} ? ' noreply' : '');
    }

    elsif($incr_decr_cmds{$method}) {
        # incr <key> <value> [noreply]\r\n
        # decr <key> <value> [noreply]\r\n
  
        $cmd->{'request'} = "$method $params{'key'} $params{'value'}" . ($params{'noreply'} ? ' noreply' : '');
    }

    elsif($touch_cmds{$method}) {
        # touch <key> <exptime> [noreply]\r\n
  
        $cmd->{'request'} = "$method $params{'key'} $params{'expires'}" . ($params{'noreply'} ? ' noreply' : '');
    }

    elsif($stats_cmds{$method}) {
        # stats <args>\r\n -- Depending on <args>, various internal data is sent by the server.
        # The kinds of arguments and the data sent are not documented in this version
        # of the protocol, and are subject to change for the convenience of memcache developers.
  
        $cmd->{'request'} = $method;
    }

    $cmd->{'request'} .= "\r\n";

    if(defined($cmd->{'value'})) {
        $cmd->{'value'} .= "\r\n";
    }

    return $self->_do_cmd($cmd, $method, $params{'noreply'}, $multi);
}

1;
