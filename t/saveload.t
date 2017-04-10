#!/usr/bin/env perl

use Path::Tiny;
use Test::More;

use PEDSnet::Lessidentify::PEDSnet_CDM;

my $less = PEDSnet::Lessidentify::PEDSnet_CDM->new;
my $tmp = Path::Tiny->tempfile;
open my $strfh, '+<', \my $str;

my(@recs) = ( {
	       person_id => 1,
	       test_date => '2014-01-02 04:05:06',
	       label => 'first'
	      },
	      {
	       person_id => 2,
	       test_date => '2014-02-03 05:06:07',
	       label => 'second'
	      },
	      {
	       person_id => 3,
	       test_date => '2014-02-03 06:07:08',
	       label => 'third'
	      },
	      {
	       person_id => 1,
	       test_date => '2014-04-05 04:05:06',
	       label => 'fourth'
	      } );

$less->scrub_record( $recs[$_] ) for 0..2;
my $want = $less->scrub_record( $recs[3] );


for my $target (($tmp->canonpath, $strfh)) {

  is($less->save_maps( $target ),
     $target,
     "Save mapping state to $target");

  my $less2 = PEDSnet::Lessidentify::PEDSnet_CDM->new;
  for (0..2) {
    last if $want->{test_date} ne $less2->remap_date( $recs[3], 'test_date' );
    $less2 = PEDSnet::Lessidentify::PEDSnet_CDM->new;
  }

  seek($target, 0, 0) if ref $target;
  
  is( $less2->load_maps( $target ),
      $less2,
      'and reload mapping state');

  is_deeply($less2->scrub_record( $recs[3] ),
	    $want,
	    'Loaded state used for scrubbing');
}

done_testing;
