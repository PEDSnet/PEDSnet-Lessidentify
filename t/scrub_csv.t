#!/usr/bin/env perl

use FindBin ();
use Path::Tiny;
use Test::More;

my $appdir = path($FindBin::Bin)->sibling('script');

unshift @INC, $appdir->canonpath;

ok(require('scrub_csv'), 'Load scrub_csv');

my $tmpin = Path::Tiny->tempfile;
my $tmpout = Path::Tiny->tempfile;

$tmpin->append(<<'EOD');
person_id,test_date,label,sibling_id,person_source_value,value_source_value,secret_value_source_value,site
5,2014-01-02,first,12,myob,alright,bye-bye,"Kids' Best Hospital"
12,2014-02-04,second,5,me,fine,not-here,"Children's Hospital Somewhere"
19,2014-03-04,third,,myself,ok,"move along","Kids' Best Hospital"
5,2014-04-05,fourth,19,I,notsogood,"nothing to see","Elsewhere Medical Center"
EOD

@ARGV = ('--cdm=PEDSnet',
	 '--preserve=value_source_value',
	 '--redact=qr/^secret/',
	 '--force=remap_label=site_id',
	 '--alias=person_id=sibling_id,notpresent=nothing',
	 '--verbose=0',
	 "$tmpin", "$tmpout");

my $app = eval { PEDSnet::Lessidentify::App::scrub_csv->new_with_options };
isa_ok($app, 'PEDSnet::Lessidentify::App::scrub_csv');
ok($app->run, 'scrub_csv runs');

my(@rslt) = map { [ split /,/, $_, 8 ] } $tmpout->lines;

isnt( $rslt[1][0], 5, 'values remapped from input');
is( $rslt[1][0], $rslt[4][0], 'same values at input are same at output');
isnt( $rslt[1][6], 'bye-bye', 'redacted specified attribute');
is( $rslt[3][5], 'ok', 'preserved specified attribute');
like( $rslt[4][-1], qr/site/, 'forced specified mapping');
is( $rslt[1][0], $rslt[2][3], 'aliased specified attribute');

my $prog = $appdir->child('scrub_csv')->canonpath;
my $msg = `$prog --cdm_type=PEDSnet --version`;

like($msg, qr/^PEDSnet::Lessidentify version/m, 'Library version');
like($msg, qr/scrub_csv version/, 'App version');

done_testing;
