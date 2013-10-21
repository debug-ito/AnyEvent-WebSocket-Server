use strict;
use warnings;
use Module::Build::Pluggable (
    'CPANfile'
);

my $builder = Module::Build::Pluggable->new(
    module_name         => 'AnyEvent::WebSocket::Server',
    license             => 'perl',
    dist_author         => q{Toshio Ito <toshioito@cpan.org>},
    dist_version_from   => 'lib/AnyEvent/WebSocket/Server.pm',
    add_to_cleanup      => [ 'AnyEvent-WebSocket-Server-*' ],
    recursive_test_files => 1,
    no_index => {
        directory => ["t", "xt", "eg", "inc"],
        file => ['README.pod'],
    },
    meta_add => {
        resources => {
            repository => 'git://github.com/debug-ito/AnyEvent-WebSocket-Server.git'
        }
    }

);

$builder->create_build_script();
