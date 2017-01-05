#!/usr/bin/env perl

use Test::More;

require_ok('PEDSnet::Lessidentify');

new_ok('PEDSnet::Lessidentify');

require_ok('PEDSnet::Lessidentify::PEDSnet_CDM');

new_ok('PEDSnet::Lessidentify::PEDSnet_CDM');

done_testing();

