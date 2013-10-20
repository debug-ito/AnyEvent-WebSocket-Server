use strict;
use warnings;
use Test::More;
use Test::Requires {
    "Twiggy::Server" => "0",
    "Net::EmptyPort" => "0",
    "AnyEvent::HTTP" => "0",
};
use Twiggy::Server;
use Net::EmptyPort qw(empty_port);
use AnyEvent::HTTP qw(http_get);
use FindBin;
use lib ($FindBin::RealBin);
use testlib::Util qw(set_timeout);
use AnyEvent;
use AnyEvent::WebSocket::Server;
use AnyEvent::WebSocket::Client;
use Try::Tiny;

set_timeout;

my $port = empty_port();
note("empty port: $port");
my $twiggy = Twiggy::Server->new(
    host => "127.0.0.1",
    port => $port
);

my $cv_server_finish = AnyEvent->condvar;
my $server = AnyEvent::WebSocket::Server->new(validator => sub { return "validated" });
$twiggy->register_service(sub {
    my ($env) = @_;
    return sub {
        my $responder = shift;
        note("server enters streaming callback");
        $cv_server_finish->begin;
        my $server_conn_cv = $server->establish_psgi($env);
        $server_conn_cv->cb(sub {
            my $cv = shift;
            my ($conn, $validate_str) = try { $cv->recv };
            if(!$conn) {
                note("server connection error");
                $responder->([400, ['Content-Type' => 'text/plain', 'Connection' => 'close'], ['invalid request']]);
                $cv_server_finish->end;
                return;
            }
            is($validate_str, "validated", "validator should be called");
            $conn->on(each_message => sub {
                my ($conn, $message) = @_;
                $conn->send($message);
            });
            $conn->on(finish => sub {
                undef $conn;
                $responder->([200, ['Content-Type' => 'text/plain', 'Connection' => 'close'], ['dummy response']]);
                $cv_server_finish->end;
            });
        });
    };
});

my $client = AnyEvent::WebSocket::Client->new;

sub test_case {
    my ($label, $code) = @_;
    note("--- $label");
    $cv_server_finish = AnyEvent->condvar;
    $code->();
}

test_case "normal echo", sub {
    my $conn = $client->connect("ws://127.0.0.1:$port/")->recv;
    note("client connection established");
    my $cv = AnyEvent->condvar;
    $conn->on(next_message => sub {
        $cv->send($_[1]->body);
    });
    $conn->send("foobar");
    is($cv->recv, "foobar", "echo OK");
    $conn->close;
    $cv_server_finish->recv;
    pass("server connection shutdown");
};

test_case "http fallback", sub {
    my $cv_client = AnyEvent->condvar;
    http_get "http://127.0.0.1:$port/", sub { $cv_client->send(@_) };
    note("send http request");
    my ($data, $headers) = $cv_client->recv;
    is($headers->{Status}, 400, "response status code OK");
    is($data, "invalid request", "response data OK");
    $cv_server_finish->recv;
    pass("server session finished");
};

done_testing;
