package testlib::Util;
use strict;
use warnings;
use Exporter qw(import);
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use Test::Memory::Cycle ();
use Test::More;
use Test::Builder;

our @EXPORT_OK = qw(start_server set_timeout memory_cycle_ok);

sub start_server {
    my ($accept_cb) = @_;
    my $cv_server_port = AnyEvent->condvar;
    tcp_server '127.0.0.1', undef, $accept_cb, sub { ## prepare cb
        my ($fh, $host, $port) = @_;
        $cv_server_port->send($port);
    };
    return $cv_server_port;
}

sub set_timeout {
    my $w;
    $w = AnyEvent->timer(after => 10, cb => sub {
        fail("Timeout");
        undef $w;
        exit 2;
    });
}

sub memory_cycle_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    local $SIG{__WARN__} = sub {
        note(shift);
    };
    return Test::Memory::Cycle::memory_cycle_ok(@_);
}

1;
