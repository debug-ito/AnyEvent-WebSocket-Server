package AnyEvent::WebSocket::Server;
use strict;
use warnings;
use Carp;
use AnyEvent::Handle;
use Protocol::WebSocket::Handshake::Server;
use Try::Tiny;
use AnyEvent::WebSocket::Connection;

our $VERSION = "0.03";

sub new {
    my ($class, %args) = @_;
    my $validator = $args{validator} || sub {};
    if(ref($validator) ne "CODE") {
        croak "validator parameter must be a code-ref";
    }
    my $self = bless {
        validator => $validator
    }, $class;
    return $self;
}

sub _create_on_error {
    my ($cv) = @_;
    return sub {
        my ($handle, $fatal, $message) = @_;
        if($fatal) {
            $cv->croak("connection error: $message");
        }else {
            warn $message;
        }
    };
}

sub _do_handshake {
    my ($cv_connection, $fh, $handshake, $validator) = @_;
    my $handle = AnyEvent::Handle->new(fh => $fh, on_error => _create_on_error($cv_connection));
    my $read_cb = sub {
        ## We don't receive handle object as an argument here. $handle
        ## is imported in this closure so that $handle becomes
        ## half-immortal.
        try {
            if(!defined($handshake->parse($handle->{rbuf}))) {
                die "handshake error: " . $handshake->error . "\n";
            }
            return if !$handshake->is_done;
            if($handshake->version ne "draft-ietf-hybi-17") {
                die "handshake error: unsupported WebSocket protocol version " . $handshake->version . "\n";
            }
            my @validator_result = $validator->($handshake->req);
            $handle->push_write($handshake->to_string);
            $cv_connection->send(AnyEvent::WebSocket::Connection->new(handle => $handle), @validator_result);
            undef $handle;
            undef $cv_connection;
        }catch {
            my $e = shift;
            $cv_connection->croak($e);
            undef $handle;
            undef $cv_connection;
        };
    };
    $handle->{rbuf} = "";
    $read_cb->();  ## in case the whole request is already consumed
    $handle->on_read($read_cb) if defined $handle;
}

sub establish {
    my ($self, $fh) = @_;
    my $cv_connection = AnyEvent->condvar;
    if(!defined($fh)) {
        $cv_connection->croak("fh parameter is mandatory for establish() method");
        return $cv_connection;
    }
    my $handshake = Protocol::WebSocket::Handshake::Server->new;
    _do_handshake($cv_connection, $fh, $handshake, $self->{validator});
    return $cv_connection;
}

sub establish_psgi {
    my ($self, $env, $fh) = @_;
    my $cv_connection = AnyEvent->condvar;
    if(!defined($env)) {
        $cv_connection->croak("psgi_env parameter is mandatory");
        return $cv_connection;
    }
    $fh = $env->{"psgix.io"} if not defined $fh;
    if(!defined($fh)) {
        $cv_connection->croak("No connection file handle provided. Maybe the PSGI server does not support psgix.io extension.");
        return $cv_connection;
    }
    my $handshake = Protocol::WebSocket::Handshake::Server->new_from_psgi($env);
    _do_handshake($cv_connection, $fh, $handshake, $self->{validator});
    return $cv_connection;
}

1;

__END__

=pod

=head1 NAME

AnyEvent::WebSocket::Server - WebSocket server for AnyEvent

=head1 SYNOPSIS

    use AnyEvent::Socket qw(tcp_server);
    use AnyEvent::WebSocket::Server;
    
    my $server = AnyEvent::WebSocket::Server->new();
    
    my $tcp_server;
    $tcp_server = tcp_server undef, 8080, sub {
        my ($fh) = @_;
        $server->establish($fh)->cb(sub {
            my $connection = eval { shift->recv };
            if($@) {
                warn "Invalid connection request: $@\n";
                close($fh);
                return;
            }
            $connection->on(each_message => sub {
                my ($connection, $message) = @_;
                $connection->send($message); ## echo
            });
            $connection->on(finish => sub {
                undef $connection;
            });
        });
    };

=head1 DESCRIPTION

This class is an implementation of the WebSocket server in an L<AnyEvent> context.

=over

=item *

Currently this module supports WebSocket protocol version 13 only. See L<RFC 6455|https://tools.ietf.org/html/rfc6455> for detail.

=item *

Currently this module does not support SSL/TLS.

=back


=head1 CLASS METHODS

=head2 $server = AnyEvent::WebSocket::Server->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<validator> => CODE (optional)

A subroutine reference to validate the incoming WebSocket request.
If omitted, it accepts the request.

The validator is called like

    @validator_result = $validator->($request)

where C<$request> is a L<Protocol::WebSocket::Request> object.

If you reject the C<$request>, throw an exception.

If you accept the C<$request>, don't throw any exception.
The return values of the C<$validator> are sent to the condition variable of C<establish()> method.

=back


=head1 OBJECT METHODS

=head2 $conn_cv = $server->establish($fh)

Establish a WebSocket connection to a client via the given connection filehandle.

C<$fh> is a filehandle for a connection socket, which is usually obtained by C<tcp_server()> function in L<AnyEvent::Socket>.

Return value C<$conn_cv> is an L<AnyEvent> condition variable.

In success, C<< $conn_cv->recv >> returns an L<AnyEvent::WebSocket::Connection> object and additional values returned by the validator.
In failure (e.g. the client sent a totally invalid request or your validator threw an exception),
C<$conn_cv> will croak an error message.

    ($connection, @validator_result) = eval { $conn_cv->recv };
    
    ## or in scalar context, it returns $connection only.
    $connection = eval { $conn_cv->recv };
    
    if($@) {
        my $error = $@;
        ...
        return;
    }
    do_something_with($connection);

You can use C<$connection> to send and receive data through WebSocket. See L<AnyEvent::WebSocket::Connection> for detail.

Note that even if C<$conn_cv> croaks, the connection socket C<$fh> remains intact.
You can communicate with the client via C<$fh> unless the client has already closed it.

=head2 $conn_cv = $server->establish_psgi($psgi_env, [$fh])

The same as C<establish()> method except that the request is in the form of L<PSGI> environment.
B<This method is experimental. The API may change in the future.>

C<$psgi_env> is a L<PSGI> environment object obtained from a L<PSGI> server.
C<$fh> is the connection filehandle.
If C<$fh> is omitted, C<< $psgi_env->{"psgix.io"} >> is used for the connection (see L<PSGI::Extensions>).

=head1 EXAMPLES

=head2 Validator option

The following server accepts WebSocket URLs such as C<ws://localhost:8080/2013/10>.

    use AnyEvent::Socket qw(tcp_server);
    use AnyEvent::WebSocket::Server;
    
    my $server = AnyEvent::WebSocket::Server->new(
        validator => sub {
            my ($req) = @_;  ## Protocol::WebSocket::Request
            
            my $path = $req->resource_name;
            die "Invalid format" if $path !~ m{^/(\d{4})/(\d{2})};
            
            my ($year, $month) = ($1, $2);
            die "Invalid month" if $month <= 0 || $month > 12;
    
            return ($year, $month);
        }
    );
    
    tcp_server undef, 8080, sub {
        my ($fh) = @_;
        $server->establish($fh)->cb(sub {
            my ($conn, $year, $month) = eval { shift->recv };
            if($@) {
                my $error = $@;
                error_response($fh, $error);
                return;
            }
            $conn->send("You are accessing YEAR = $year, MONTH = $month");
            $conn->on(finish => sub { undef $conn });
        });
    };

=head1 SEE ALSO

=over

=item L<AnyEvent::WebSocket::Client>

L<AnyEvent>-based WebSocket client implementation.

=item L<Net::WebSocket::Server>

Minimalistic stand-alone WebSocket server. It uses its own event loop mechanism.

=item L<Net::Async::WebSocket>

Stand-alone WebSocket server and client implementation using L<IO::Async>


=back

=head1 AUTHOR

Toshio Ito, C<< <toshioito at cpan.org> >>

=head1 REPOSITORY

L<https://github.com/debug-ito/AnyEvent-WebSocket-Server>

=head1 ACKNOWLEDGEMENTS

Graham Ollis (plicease) - author of L<AnyEvent::WebSocket::Client>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Toshio Ito.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

