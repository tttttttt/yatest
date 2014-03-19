package Memcached::Client2;

BEGIN {
    $Memcached::Client2::VERSION = '0.01';
}

use strict;
use warnings;
use Data::Dumper;
use IO::Socket::INET;
use IO::Select;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Memcached::Client2::Util qw /
    parse_complex_response
    parse_complex_response2
    validate_params
    %all_cmds
    %cas_cmds
    %storage_cmds
    %retrieval_cmds
    %deletion_cmds
    %incr_decr_cmds
    %touch_cmds
    %stats_cmds
/;

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

    if(!$self->{'params'}->{'async'}) {
        $self->_connect;
    }
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

sub close {
    my ($self) = @_;

    if ($self->{'socket'}) {
        $self->{'socket'}->close;
    }
}

sub DESTROY {
    my ($self) = @_;

    $self->close;
}

sub _write_request {
    my ($self, $cmd, $method) = @_;

    my $socket = $self->{'socket'};

    my $data = $cmd->{'request'} . (defined($cmd->{'value'}) ? $cmd->{'value'} : '');

    print({ $socket } $data);
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
        return "error: $row";
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

    return parse_complex_response($method, \@data, $multi);
}

sub _async_request {
    my ($self, $cmd, $method, $noreply, $multi) = @_;

    my $status = 0;
    my $data;

    my $done = AnyEvent->condvar;

    my $guard = tcp_connect($self->{'params'}->{'host'}, $self->{'params'}->{'port'}, sub {
        my ($fh, $host, $port, $retry) = @_
            or die("async connect failed ($!)");

        my $handle;

        $handle = AnyEvent::Handle->new(
            'fh' => $fh,
            'on_error' => sub {
               $_[0]->destroy;
            },
            'on_eof' => sub {
               $handle->destroy;
            },
        );

        my $cmd = $cmd->{'request'} . (defined($cmd->{'value'}) ? $cmd->{'value'} : '');

        $handle->push_write($cmd);
        $handle->push_read('line' => sub {
            my ($handle, $line) = @_;

            if($line =~ m/^(?:ERROR|CLIENT_ERROR|SERVER_ERROR)/) {
                $status = "error: $line";
            } else {
                $data = $line;

                if($storage_cmds{$method}) {
                    if($line eq "STORED") {
                        $status = 1;
                    } else {
                        $status = undef;
                    }
                } elsif($deletion_cmds{$method}) {
                    if($line eq "DELETED") {
                        $status = 1;
                    } else {
                        $status = undef;
                    }
                } elsif($incr_decr_cmds{$method}) {
                    if($line eq "NOT_FOUND") {
                        $status = undef;
                    } else {
                        $status = trim($line);
                    }
                } elsif($touch_cmds{$method}) {
                    if($line eq "TOUCHED") {
                        $status = 1;
                    } else {
                        $status = undef;
                    }
                }
            }

            if(defined($status) && $status == 0) {
                $handle->on_read(sub {
                    my $row = $_[0]->rbuf;
                    $_[0]->rbuf = '';

                    if($retrieval_cmds{$method}) {
                        $data = $row;
                    } elsif($stats_cmds{$method}) {
                        $data = $row;
                    }
                });

                $done->send;
            } else {
                $done->send;
            }
        });
    });

    $done->recv;

    if(defined($status) && $status == 0) {
        return parse_complex_response2($method, $data, $multi);
    } else {
        return $status;
    }
}

sub _do_cmd {
    my ($self, $cmd, $method, $noreply, $multi) = @_;

    if($self->{'params'}->{'async'}) {
        my $data;
        return $self->_async_request($cmd, $method, $noreply, $multi);
    } else {
        $self->_write_request($cmd, $method);
        return $self->_read_response($method, $noreply, $multi);
    }
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
