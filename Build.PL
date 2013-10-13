use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'AnyEvent::WebSocket::Server',
    license             => 'perl',
    dist_author         => q{Toshio Ito <toshioito@cpan.org>},
    dist_version_from   => 'lib/AnyEvent/WebSocket/Server.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'perl' => 5.006,
    },
    add_to_cleanup      => [ 'AnyEvent-WebSocket-Server-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
