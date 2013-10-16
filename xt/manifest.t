#!perl -T

use strict;
use warnings;
use Test::More;


eval "use Test::CheckManifest 0.9";
plan skip_all => "Test::CheckManifest 0.9 required" if $@;

local $TODO = "do packaging!";
ok_manifest();
