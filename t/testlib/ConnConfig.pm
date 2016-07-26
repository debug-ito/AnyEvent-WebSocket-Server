package testlib::ConnConfig;
use strict;
use warnings;
use Test::More;

sub _new {
    my ($class, %fields) = @_;
    my $self = bless {
        map { ($_ => $fields{$_}) } qw(label server_args client_args client_handle_base scheme address)
    }, $class;
    return $self;
}

sub all_conn_configs {
    my ($class) = @_;
    return (
        $class->_new(
            label => "conn:ws",
            server_args => [],
            client_args => [],
            client_handle_base => [],
            scheme => "ws",
            address => "127.0.0.1"
        ),
        ## TODO: create private key / certificate pair.
        ## 
        ## $class->new(
        ##     label => "wss",
        ##     server_args => [...]
        ## )
    );
}

sub for_all_conn_configs {
    my ($class, $code) = @_;
    foreach my $cconfig ($class->all_conn_configs) {
        subtest $cconfig->label, { $code->($cconfig) };
    }
}

sub label { $_[0]->{label} }
sub server_args { @{$_[0]->{server_args}} }
sub client_args { @{$_[0]->{client_args}} }

sub client_handle_args {
    my ($self, $port) = @_;
    return (
        connect => [$self->{address}, $port],
        @{$self->{client_handle_base}}
    );
}

sub connect_url {
    my ($self, $port, $path) = @_;
    my $port_str = defined($port) ? ":$port" : "";
    my $path_str = defined($path) ? $path : "";
    return qq{$self->{scheme}://$self->{address}$port_str$path_str};
}

1;
