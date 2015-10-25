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

sub handshake_error_case {
    my (%args) = @_;
    my $handshake = $args{handshake};
    my $exp_error_pattern = $args{exp_error_pattern};
    my $label = $args{label};
    note("--- $label");
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => $handshake
    );
    my $finish_cv = AnyEvent->condvar;
    my $port_cv = start_server sub {
        my ($fh) = @_;
        $s->establish($fh)->cb(sub {
            my ($conn) = eval { shift->recv };
            like $@, $exp_error_pattern, $label;
            is $conn, undef;
            shutdown $fh, 0;
            undef $fh;
            $finish_cv->send;
        });
    };
    my $port = $port_cv->recv;
    my $client_conn_cv = AnyEvent::WebSocket::Client->new->connect("ws://127.0.0.1:$port/hoge");
    $finish_cv->recv;
    my ($client_conn) = eval { $client_conn_cv->recv };
    is $client_conn, undef, "client connection should not be obtained";
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
    note("Response:");
    note($raw_res);
    like $raw_res, qr{^HTTP/1\.[10] 101}i, "101 status line OK";
    like $raw_res, qr{^Sec-WebSocket-Protocol\s*:\s*mytest\.subprotocol}im, "subprotocol is set OK";
}

{
    note("raw response");
    my $input_response = "This must be rejected by the client\r\n\r\n";
    my $s = AnyEvent::WebSocket::Server->new(
        handshake => sub {
            my ($req, $res) = @_;
            return "This must be rejected by the client\r\n\r\n";
        }
    );
    my $finish_cv = AnyEvent->condvar;
    my $port = start_passive_server($s, sub { $finish_cv->send })->recv;
    my $raw_res = get_raw_response($port, "/foobar")->recv;
    $finish_cv->recv;
    note("Response:");
    note($raw_res);
    is $raw_res, $input_response, "raw response OK";
}

handshake_error_case(
    label => "throw exception",
    handshake => sub { die "BOOM!" },
    exp_error_pattern => qr/BOOM\!/,
);

handshake_error_case(
    label => "no return",
    handshake => sub { return () },
    exp_error_pattern => qr/handshake response was undef/i,
);

done_testing;
