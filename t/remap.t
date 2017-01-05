#!/usr/bin/env perl

use Test::More;

use PEDSnet::Lessidentify::PEDSnet_CDM;

my $less = PEDSnet::Lessidentify::PEDSnet_CDM->new;

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
	       test_date => '2014-04-05 07:08:09',
	       label => 'fourth'
	      } );
	     

foreach my $pair ( [ qw/ remap_id person_id / ],
		   [ qw/ remap_label label / ],
		   [ qw/ remap_date test_date / ],
		   [ qw/ remap_datetime test_date / ]) {

  my($method, $key) = @$pair;
  my(@newvals) = map { [ $less->$method($_, $key) ] } @recs;
  my(%unique) = map { $_->[1] => 1 } @newvals;

  is( scalar @newvals,
      scalar @recs,
      "$method returns right number of results");
  ok(keys %unique > 1, "$method returns different results");
  is_deeply( [ map { $_->[0] } @newvals ],
	     [ map { $_->{$key} } @recs ],
	     "$method returns correct original values");
  is( $newvals->[0]->[1], $newvals->[-1]->[1],
      "$method maps same source to same substitute");
}

like(scalar $less->remap_date({ person_id => 1,
				 testme => '2014-01-15 12:34:56' }, 'testme'),
     qr/^\d{4}-\d{2}-\d{2}$/, 'remap_date truncates to date');

like(scalar $less->remap_datetime_always({ person_id => 1,
					   testme => '2014-01-15' }, 'testme'),
     qr/\d\d:\d\d:\d\d$/, 'remap_datetime_always adds time');

like(scalar $less->remap_datetime({ person_id => 1,
				    testme => '2014-01-15 00:00:00' }, 'testme'),
     qr/00:00:00$/,
     'remap_datetime truncates to to midnight with midnight input');


# Protect against chance offset that correctly remaps 12:34:56 to
# 00:00:00 - 1 in 1,036,800 that it'd happen 12 times in a row
my $pid = 1;
for (1..12) {
  my $remap = $less->remap_datetime({ person_id => $pid,
				      testme => '2014-01-15 12:34:56' },
				    'testme');
  last if $remap !~ /00:00:00$/;
  $pid++;
}
unlike(scalar $less->remap_datetime({ person_id => $pid,
				      testme => '2014-01-15 12:34:56' },
				    'testme'),
     qr/00:00:00$/,
     "...and doesn't truncate to to midnight with non-midnight input");

like(scalar $less->remap_label({ person_id => 1, greatest_fear => 'bugs' },
			       'greatest_fear'),
     qr/^greatest_fear_\d+$/,
    'remap_label preserves label');

done_testing;
