
on "test" => sub {
    requires "Test::More";
    requires "Test::Memory::Cycle";
    requires "AnyEvent";
    requires "AnyEvent::Socket";
    requires "AnyEvent::WebSocket::Client", "0.15";
    requires "Scalar::Util";
};
