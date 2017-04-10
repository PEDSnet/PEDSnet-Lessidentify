#!/usr/bin/env perl

use FindBin ();
use Path::Tiny;
use Test::More;

unshift @INC, path($FindBin::Bin)->sibling('script')->canonpath;

ok(require('scrub_csv'), 'Load scrub_csv');

my $tmpin = Path::Tiny->tempfile;
my $tmpout = Path::Tiny->tempfile;

$tmpin->append(<<'EOD');
person_id,test_date,label,person_source_value,value_source_value,secret_value_source_value,site
5,2014-01-02,first,myob,alright,bye-bye,"Kids' Best Hospital"
12,2014-02-04,second,me,fine,not-here,"Children's Hospital Somewhere"
19,2014-03-04,third,myself,ok,"move along","Kids' Best Hospital"
5,2014-04-05,fourth,I,notsogood,"nothing to see","Elsewhere Medical Center"
EOD

@ARGV = ('--cdm=PEDSnet',
	 '--preserve=value_source_value',
	 '--redact=qr/^secret/',
	 '--force=remap_label=site_id',
	 "$tmpin", "$tmpout");

my $app = eval { PEDSnet::Lessidentify::App::scrub_csv->new_with_options };
isa_ok($app, 'PEDSnet::Lessidentify::App::scrub_csv');
ok($app->run, 'scrub_csv runs');

my(@rslt) = map { [ split /,/ ] } $tmpout->lines;

isnt( $rslt[1][0], 5, 'values remapped from input');
is( $rslt[1][0], $rslt[4][0], ' values at input are same at output');
isnt( $rslt[1][5], 'bye-bye', 'redacted specified attribute');
is( $rslt[3][4], 'ok', 'preserved specified attribute');
like( $rslt[4][-1], qr/site/, 'forced specified mapping');

done_testing;
