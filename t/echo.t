use strict;
use warnings;
use Test::More;
use Test::Memory::Cycle;
use FindBin;
use lib ($FindBin::RealBin);
use testlib::Util qw(start_server);
use AnyEvent::WebSocket::Server;
use AnyEvent::WebSocket::Client;
no utf8;

my @server_conns = ();
my $cv_server_finish = AnyEvent->condvar;

my $cv_port = start_server sub { ## accept cb
    my ($fh) = @_;
    AnyEvent::WebSocket::Server->new->establish($fh)->cb(sub {
        my $conn = shift->recv;
        push(@server_conns, $conn);
        $conn->on(each_message => sub {
            my ($conn, $message) = @_;
            $conn->send($message);
        });
        $conn->on(finish => sub {
            $cv_server_finish->send;
        });
    });
};

my $client_conn = AnyEvent::WebSocket::Client->new->connect("ws://127.0.0.1:" . $cv_port->recv . "/")->recv;

foreach my $case (
    {label => "0 bytes", data => ""},
    {label => "10 bytes", data => "a" x 10},
    {label => "256 bytes", data => "a" x 256},
    {label => "zero", data => "0"},
    {label => "encoded UTF-8", data => 'ＵＴＦー８ＷｉｄｅＣｈａｒａｃｔｅｒｓ'},
) {
    my $cv_received = AnyEvent->condvar;
    $client_conn->on(next_message => sub {
        my ($c, $message) = @_;
        $cv_received->send($message->body);
    });
    $client_conn->send($case->{data});
    is($cv_received->recv, $case->{data}, "$case->{label}: echo OK");
}

is(sclar(@server_conns), 1, "1 server connection");
memory_cycle_ok($server_conns[0], "free of memory cycle on Connection");  ## is it true?

$client_conn->close();
$cv_server_finish->recv;

memory_cycle_ok($server_conns[0], "free of memory cycle on Connection");  ## is it true?


done_testing;

