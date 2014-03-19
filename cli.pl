#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use IO::Socket::INET;

use constant BASENAME => basename($0);
use constant MAX_KEY_LENGTH => 250;
use constant EXIT_OK => 0;
use constant EXIT_FAILURE => 1;

sub trim {
  my ($text) = @_;
  
  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  
  return $text;
}

sub usage {
  print(STDERR <<USAGE);
@{[BASENAME]} [--host <host>] [--port <port>]
USAGE
}

sub main {
  my %opts;
  
  my $rv = GetOptions(
    'help'   => \$opts{'help'},
    'host=s' => \$opts{'host'},
    'port=i' => \$opts{'port'},
  );

  if(!$rv || $opts{'help'}) {
    usage();
    exit(EXIT_FAILURE);
  }

  my $socket = new IO::Socket::INET(
    'PeerHost' => $opts{'host'} || '127.0.0.1',
    'PeerPort' => $opts{'port'} || '11211',
    'Proto' => 'tcp',
    'Timeout' => 180,
  ) or die("socket failed ($!)");
  
  print("Crtl+C for exit\n");

  my %cas_cmds = (
    'cas' => 1,
  );

  my %storage_cmds = (
    'add' => 1,
    'append' => 1,
    'prepend' => 1,
    'replace' => 1,
    'set' => 1,
    %cas_cmds,
  );

  my %retrieval_cmds = (
    'get' => 1,
    'gets' => 1,
  );

  my %deletion_cmds = (
    'delete' => 1,
  );

  my %incr_decr_cmds = (
    'decr' => 1,
    'incr' => 1,
  );

  my %touch_cmds = (
    'touch' => 1,
  );

  my %stats_cmds = (
    'stats' => 1,
  );
  
  my %all_cmds = (
    %storage_cmds,
    %retrieval_cmds,
    %deletion_cmds,
    %incr_decr_cmds,
    %touch_cmds,
    %stats_cmds
  );

  while(1) {
    my ($cmd_name, $key, $value, $flags, $expires, $noreply, $cas_unique);

    CMD:
      while(1) {
        print('command: ');
        my $cmd_str = <STDIN>;
        $cmd_name = trim($cmd_str);
  
        next CMD if(!$cmd_name);
        print("command is invalid, try again\n") and next CMD if(!$all_cmds{$cmd_name});
        last;
      }

    if($storage_cmds{$cmd_name} || $deletion_cmds{$cmd_name} || $touch_cmds{$cmd_name} || $incr_decr_cmds{$cmd_name} || $retrieval_cmds{$cmd_name}) {
      KEY:
        while(1) {
          print('key: ');
          my $key_str = <STDIN>;
          $key = trim($key_str);
  
          next KEY if(!$key);
          print("key is too long, try again\n") and next KEY if(length($key) > MAX_KEY_LENGTH);
          print("key includes control character(s), try again\n") and next KEY if($key =~ m/[[:cntrl:]]/);
          # $key может содержать несколько ключей, разделенных пробелами -- только для %retrieval_cmds
          print("key includes whitespace(s), try again\n") and next KEY if(!$retrieval_cmds{$cmd_name} && $key =~ m/[[:space:]]/);
          last;
        }

      if($storage_cmds{$cmd_name}) {
        FLAGS:
          while(1) {
            print('flags: ');
            my $flags_str = <STDIN>;
            $flags = trim($flags_str);

            next FLAGS if($flags eq '');
            last;
          }
      }

      if($storage_cmds{$cmd_name} || $incr_decr_cmds{$cmd_name}) {
        VALUE:
          while(1) {
            print('value: ');
            my $value_str = <STDIN>;
            $value = trim($value_str);
      
            next VALUE if(!$value);
            last;
          }
      }

      if($storage_cmds{$cmd_name} || $touch_cmds{$cmd_name}) {
        EXPIRES:
          while(1) {
            print('expires: ');
            my $expires_str = <STDIN>;
            $expires = trim($expires_str);
      
            next EXPIRES if($expires eq '');
            print("expires has invalid value, try again\n") and next EXPIRES if($expires !~ m/\d+/);
            last;
          }
      }

      if($cas_cmds{$cmd_name}) {
        CAS_UNIQUE:
          while(1) {
            print('cas_unqiue: ');
            my $cas_unique_str = <STDIN>;
            $cas_unique = trim($cas_unique_str);

            next CAS_UNIQUE if($cas_unique eq '');
            last;
          }
      }

      if(!$retrieval_cmds{$cmd_name}) {
        NOREPLY:
          while(1) {
            print('noreply (y|n): ');
            my $noreply_str = <STDIN>;
            $noreply = lc(trim($noreply_str));

            next NOREPLY if($noreply eq '');
            print("noreply has invalid value, try again\n") and next EXPIRES if($noreply ne 'y' && $noreply ne 'n');
            last;
          }
      }
      
    }

    my $cmd;

    if($storage_cmds{$cmd_name}) {
      my $bytes = length($value);

      if($cas_cmds{$cmd_name}) {
        # cas <key> <flags> <exptime> <bytes> <cas unique> [noreply]\r\n
        $cmd = "$cmd_name $key $flags $expires $bytes $cas_unique" . ($noreply eq 'y' ? ' noreply' : '');
      } else {
        # <command name> <key> <flags> <exptime> <bytes> [noreply]\r\n
        $cmd = "$cmd_name $key $flags $expires $bytes" . ($noreply eq 'y' ? ' noreply' : '');
      }
    }

    elsif($retrieval_cmds{$cmd_name}) {
      # get <key>*\r\n
      # gets <key>*\r\n

      # $key может содержать несколько ключей, разделенных пробелами
      $cmd = "$cmd_name $key";
    }

    elsif($deletion_cmds{$cmd_name}) {
      # delete <key> [noreply]\r\n

      $cmd = "$cmd_name $key" . ($noreply eq 'y' ? ' noreply' : '');
    }

    elsif($incr_decr_cmds{$cmd_name}) {
      # incr <key> <value> [noreply]\r\n
      # decr <key> <value> [noreply]\r\n

      $cmd = "$cmd_name $key $value" . ($noreply eq 'y' ? ' noreply' : '');
    }

    elsif($touch_cmds{$cmd_name}) {
      # touch <key> <exptime> [noreply]\r\n

      $cmd = "$cmd_name $key $expires" . ($noreply eq 'y' ? ' noreply' : '');
    }

    elsif($stats_cmds{$cmd_name}) {
      # stats <args>\r\n -- Depending on <args>, various internal data is sent by the server.
      # The kinds of arguments and the data sent are not documented in this version
      # of the protocol, and are subject to change for the convenience of memcache developers.

      $cmd = $cmd_name;
    }

    $cmd .= "\r\n";

    if($storage_cmds{$cmd_name}) {
      print($socket $cmd, $value, "\r\n");

    } else {
      print($socket $cmd);
    }

    while(my $row = <$socket>) {
      print("> $row");
      
      # "ERROR\r\n", "CLIENT_ERROR <error>\r\n", "SERVER_ERROR <error>\r\n"

      # stats
      if($stats_cmds{$cmd_name} && $row eq "END\r\n") {
        last;
      }

      # retrieval
      elsif($retrieval_cmds{$cmd_name} && $row eq "END\r\n") {
        last;
      }

      # storage
      elsif($storage_cmds{$cmd_name} && $row eq "STORED\r\n"
         || $row eq "NOT_STORED\r\n"
         || $row eq "NOT_FOUND\r\n"
         || $row eq "EXISTS\r\n") {
        last;
      }

      # deletion
      elsif($deletion_cmds{$cmd_name} && $row eq "DELETED\r\n"
         || $row eq "NOT_FOUND\r\n") {
        last;
      }

      # incr/decr
      elsif($incr_decr_cmds{$cmd_name} && ($row eq "NOT_FOUND\r\n"
         || $row =~ m/^\d+\r\n$/)) {
        last;
      }
      
      # touch
      elsif($touch_cmds{$cmd_name} && $row eq "TOUCHED\r\n"
         || $row eq "NOT_FOUND\r\n") {
        last;
      }
    }
  }

  $socket->close();
}

main;
