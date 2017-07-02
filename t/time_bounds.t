#!/usr/bin/env perl

use Test::More;
use Log::Any::Adapter::Carp;  # dzil food

use PEDSnet::Lessidentify::PEDSnet_CDM;

my $message;

$SIG{__WARN__} = sub { $message .= shift };

my(@recs) = ( {
	       person_id => 1,
	       test_date => '2014-01-02 04:05:06'
	      },
	      {
	       person_id => 1,
	       test_date => '2016-02-03 05:06:07'
	      },
	      {
	       person_id => 1,
	       test_date => '2017-07-03 08:09:10'
	      } );
	     
my $less = PEDSnet::Lessidentify::PEDSnet_CDM->
  new( before_date_threshold => '2015-12-01',
       after_date_threshold => '2016-05-02',
       date_threshold_action => 'warn',
       verbose => -1);

$message = '';
my $remapped = $less->scrub_record($recs[1]);
isnt($remapped->{test_date}, $recs[1]->{test_date}, 'remap in-bounds date');

$message = '';
$less->scrub_record($recs[0]);
like($message, qr/Early date warning: remapped test_date 2014-01-02/, 'early warning');

$message = '';
$less->scrub_record($recs[2]);
like($message, qr/Late date warning: remapped test_date 2017-07-03/, 'late warning');

$message = '';
$less = PEDSnet::Lessidentify::PEDSnet_CDM->
  new( before_date_threshold => '2015-12-01',
       after_date_threshold => '2016-05-02',
       date_threshold_action => 'none',
       verbose => -1);
$less->scrub_record($recs[0]);
is($message, '', 'respect "none" action');

$message = '';
$less = PEDSnet::Lessidentify::PEDSnet_CDM->
  new( before_date_threshold => '2015-08-01',
       after_date_threshold => '2016-08-04',
       date_threshold_action => 'retry',
       verbose => -1);
$less->scrub_record($recs[0]);
like($message, qr/Can't get offset within date threshold/, "can't remap in bounds");
like($message, qr/Early date warning: remapped test_date 2014-01-02/, 'plus early warning');
$message = '';
$less->scrub_record($recs[1]);
is($message, '', 'but no complaints with an in-bounds date');
$message = '';
$less->scrub_record($recs[2]);
like($message, qr/Late date warning: remapped test_date 2017-07-03/,
     'and late warning with an out-of-bounds date');


$message = '';
$less = PEDSnet::Lessidentify::PEDSnet_CDM->
  new( before_date_threshold => '2015-12-01',
       after_date_threshold => '2016-05-02',
       date_threshold_action => 'retry',
       verbose => -1);
my $remapped = $less->scrub_record($recs[1]);
isnt($remapped->{test_date}, $recs[1]->{test_date}, 'remap in-bounds date');
is($message, '', 'with no warning when "retry" active');

done_testing;
