package AnyEvent::WebSocket::Server;
use strict;
use warnings;

1;

__END__

=head1 SYNOPSIS

    use AnyEvent::Socket qw(tcp_server);
    use AnyEvent::WebSocket::Server;
        
    my $server = AnyEvent::WebSocket::Server->new();
        
    my $tcp_server;
    $tcp_server = tcp_server undef, 8080, sub {
        my ($fh) = @_;
        $server->establish(fh => $fh)->cb(sub {
            my $connection = eval { shift->recv };
            if($@) {
                warn "Invalid connection request: $@\n";
                close($fh);
                return;
            }
            $connection->send("bye!");
            $connection->close();
            undef $tcp_server;   # shutdown the listening port
        });
    };

=head1 DESCRIPTION

This class is an implementation of the WebSocket server in an L<AnyEvent> context.
This version does not support SSL/TLS.

=head1 CLASS METHODS

=head2 $server = AnyEvent::WebSocket::Server->new()

The constructor.
In this version, it takes no argument.

=head1 OBJECT METHODS

=head2 $conn_cv = $server->establish(%args)

Establish a WebSocket connection to a client via the given connection method.

Fields in C<%args> are:

=over

=item C<fh> => FILEHANDLE (semi-optional)

A filehandle for a connection socket, which is usually obtained by C<tcp_server()> function in L<AnyEvent::Socket>.
If C<psgi_env> field is omitted, this field is mandatory.

=item C<psgi_env> => L<PSGI> environment object (semi-optional)

A L<PSGI> environment object obtained from a L<PSGI> server.
If C<fh> field is omitted, this field is mandatory and C<< $env->{"psgix.io"} >> is used for the connection (see L<PSGI::Extensions>).

=item C<validator> => CODE (optional)

A subroutine reference to validate the incoming WebSocket request.
If omitted, it accepts the request.

The validator is called like

    $validator->($request)

where C<$handshake> is a C<Protocol::WebSocket::Request> object.
If you reject the C<$request>, throw an exception, then the returned C<$conn_cv> will croak the same exception.
If you accept the C<$request>, just don't throw any exception.

=back

Return value C<$conn_cv> is an L<AnyEvent> condition variable.

In success, a L<AnyEvent::WebSocket::Connection> object is sent through the C<$conn_cv>.
In failure, C<$conn_cv> will croak an error message.

    $connection = eval { $conn_cv->recv };
    if($@) {
        my $error = $@;
        ...
        return;
    }
    do_something_with($connection);

You can use C<$connection> to send and receive data through WebSocket. See L<AnyEvent::WebSocket::Connection> for detail.

Note that even if C<$conn_cv> croaks, the connection socket C<$fh> remains intact.
You have to close the socket manually if it's necessary.



=head1 AUTHOR

Toshio Ito, C<< <toshioito at cpan.org> >>

=head1 REPOSITORY

=head1 ACKNOWLEDGEMENTS

Graham Ollis (plicease) - author of L<AnyEvent::WebSocket::Client>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Toshio Ito.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

