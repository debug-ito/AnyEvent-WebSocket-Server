
requires "Carp";
requires "Try::Tiny";
requires "AnyEvent::Handle";
requires "AnyEvent::WebSocket::Client", "0.20";
requires "Protocol::WebSocket::Handshake::Server";

on "test" => sub {
    requires "Test::More";
    requires "Test::Memory::Cycle";
    requires "Test::Requires";
    requires "AnyEvent";
    requires "AnyEvent::Socket";
    requires "AnyEvent::Handle";
    requires "AnyEvent::WebSocket::Client", "0.20";
    requires "Scalar::Util";
    requires "Try::Tiny";
    requires "Protocol::WebSocket::Handshake::Client";
    requires "Protocol::WebSocket::Frame";
};

on 'configure' => sub {
    requires 'Module::Build::Pluggable',           '0.09';
    requires 'Module::Build::Pluggable::CPANfile', '0.02';
};
