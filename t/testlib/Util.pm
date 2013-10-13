package testlib::Util;
use strict;
use warnings;
use Exporter qw(import);
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);

our @EXPORT_OK = qw(start_server);

sub start_server {
    my ($accept_cb) = @_;
    my $cv_server_port = AnyEvent->condvar;
    tcp_server '127.0.0.1', undef, $accept_cb, sub { ## prepare cb
        my ($fh, $host, $port) = @_;
        $cv_server_port->send($port);
    };
    return $cv_server_port;
}

1;


