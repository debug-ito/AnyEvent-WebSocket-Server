use strict;
use warnings;
use Test::More;
use FindBin;
use lib ($FindBin::RealBin);
use testlib::Util qw(start_server set_timeout);
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::WebSocket::Server;
use AnyEvent::WebSocket::Client;
use Protocol::WebSocket::Handshake::Client;

set_timeout;

sub start_passive_server {
    my ($websocket_server, $finish_cb) = @_;
    $finish_cb ||= sub {};
    my $port_cv = start_server sub {
        my ($fh) = @_;
        $websocket_server->establish($fh)->cb(sub {
            my $conn = shift->recv;
            $conn->on(finish => sub {
                undef $conn;
                $finish_cb->();
            });
        });
    };
    return $port_cv;
}

sub client_connection {
    my ($target_url) = @_;
    return AnyEvent::WebSocket::Client->new->connect($target_url)->recv;
}

sub get_raw_response {
    my ($port, $path) = @_;
    my $raw_response_cv = AnyEvent->condvar;
    my $hs = Protocol::WebSocket::Handshake::Client->new(url => "ws://127.0.0.1:$port$path");
    my $handle; $handle = AnyEvent::Handle->new(
        connect => ["127.0.0.1", $port],
        on_error => sub { $raw_response_cv->croak("client handle error: $_[2]"); },
        on_connect => sub {
            my ($handle) = @_;
            $handle->push_write($hs->to_string);
        },
        on_read => sub {
            my ($handle) = @_;
            if($handle->{rbuf} =~ s/^(.+\r\n\r\n)//s) {
                $raw_response_cv->send($1);
                $handle->push_shutdown();
                return;
            }
        },
        on_eof => sub {
            undef $handle;
        }
    );
    return $raw_response_cv;
}

{
    note("--- basic IO");
    my $called = 0;
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($req, $res) = @_;
            $called = 1;
            ok wantarray, "handshake should be called in list context";
            isa_ok $req, "Protocol::WebSocket::Request";
            isa_ok $res, "Protocol::WebSocket::Response";
            return $res;
        }
    );
    my $finish_cv = AnyEvent->condvar;
    my $port = start_passive_server($s, sub { $finish_cv->send })->recv;
    my $client_conn = client_connection("ws://127.0.0.1:$port/websocket");
    $client_conn->close;
    $finish_cv->recv;
    ok $called;
}

{
    note("--- handshake is called for each request");
    my @resource_names = ();
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($req, $res) = @_;
            push @resource_names, $req->resource_name;
            return $res;
        }
    );
    my $finish_cv;
    my $port = start_passive_server($s, sub { $finish_cv->send })->recv;
    foreach my $path (
        "/", "/foo", "/foo/bar"
    ) {
        @resource_names = ();
        $finish_cv = AnyEvent->condvar;
        my $client_conn = client_connection("ws://127.0.0.1:$port$path");
        $client_conn->close;
        $finish_cv->recv;
        is_deeply \@resource_names, [$path], "request resource name should be '$path'";
    }
}

{
    note("-- other_results");
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($req, $res) = @_;
            return ($res, "hoge", 256, $res->resource_name);
        }
    );
    my @got_other_results = ();
    my $finish_cv = AnyEvent->condvar;
    my $port_cv = start_server sub {
        my ($fh) = @_;
        $s->establish($fh)->cb(sub {
            my ($conn, @other_results) = shift->recv;
            push @got_other_results, @other_results;
            $conn->on(finish => sub {
                undef $conn;
                $finish_cv->send;
            });
        });
    };
    my $port = $port_cv->recv;
    my $client_conn = client_connection("ws://127.0.0.1:$port/HOGE");
    $client_conn->close;
    $finish_cv->recv;
    is_deeply \@got_other_results, ["hoge", 256, "/HOGE"];
}

{
    note("--- response with subprotocol");
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($req, $res) = @_;
            $res->subprotocol("mytest.subprotocol");
            return $res;
        }
    );
    my $finish_cv = AnyEvent->condvar;
    my $port = start_passive_server($s, sub { $finish_cv->send })->recv;
    my $raw_res = get_raw_response($port, "/hogehoge")->recv;
    $finish_cv->recv;
    like $raw_res, qr{^HTTP/1\.[10] 101 Upgrade}i, "Upgrade status line OK";
    like $raw_res, qr{^Sec-WebSocket-Protocol\s*:\s*mytest\.subprotocol}im, "subprotocol is set OK";
}

fail("throw exception");
fail("raw response");
fail("undef response");

done_testing;
