use strict;
use warnings;
use Test::More;
use FindBin;
use lib ($FindBin::RealBin);
use testlib::Util qw(start_server set_timeout);
use AnyEvent::WebSocket::Server;
use AnyEvent::WebSocket::Client;

set_timeout;

{
    note("--- basic IO");
    my $called = 0;
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($res, $req) = @_;
            $called = 1;
            ok wantarray, "handshake should be called in list context";
            isa_ok $req, "Protocol::WebSocket::Request";
            isa_ok $res, "Protocol::WebSocket::Response";
            return $res;
        }
    );
    my $port_cv = start_server sub {
        my ($fh) = @_;
        $s->establish($fh)->cb(sub {
            my $conn = shift->recv;
            $conn->on(finish => sub { undef $conn });
        });
    };
    my $port = $port_cv->recv;
    my $client_conn = AnyEvent::WebSocket::Client->new->connect("ws://127.0.0.1:$port/websocket")->recv;
    $client_conn->close;
    ok $called;
}

fail("handshake is called for each request");
fail("other_results");
fail("throw exception");
fail("response with subprotocol");
fail("raw response");
fail("undef response");

done_testing;
