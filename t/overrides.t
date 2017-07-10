#!/usr/bin/env perl

use Test::More;

use PEDSnet::Lessidentify::PEDSnet_CDM;

my(@recs) = ( {
	       person_id => 1,
	       test_date => '2014-01-02 04:05:06',
	       label => 'first',
	       sibling_id => 3,
	       person_source_value => 'myob',
	       value_source_value => 'alright',
	       secret_value_source_value => 'bye-bye',
	       site_id => "Kids' Best Hospital",
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
	     
my $less = PEDSnet::Lessidentify::PEDSnet_CDM->
  new( redact_attributes => [ 'label', qr/^secret/ ],
       preserve_attributes => [ qr/value_source_value$/ ],
       force_mappings => { remap_label => [ 'site_id' ] },
       alias_attributes => { person_id => 'sibling_id' });

my $remapped = $less->scrub_record($recs[0]);
ok( !defined($remapped->{label}), 'Redacted specified attribute');
ok( !defined($remapped->{person_source_value}),
    'Still redacted default attribute');

is($remapped->{value_source_value}, 'alright',
   'Preserved specified value');
ok( !defined($remapped->{secret_value_source_value}),
    'Redaction takes precedence over preservation');

like($remapped->{site_id}, qr/^site_id_\d+$/,
     'Forced mapping applied');

my $sib = $less->scrub_record($recs[2]);
is($sib->{person_id}, $remapped->{sibling_id},
   'Correctly aliases attribute');

done_testing;
