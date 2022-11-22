#!perl

use 5.011;
use strict;
use warnings;

package PEDSnet::Lessidentify::PCORnet_CDM;

our($VERSION) = '3.00';

use Moo 2;

use PEDSnet::Lessidentify;
extends 'PEDSnet::Lessidentify';


=head1 NAME

PEDSnet::Lessidentify::PCORnet_CDM - Make a PCORnet CDM dataset less identifiable

=head1 SYNOPSIS

  use PEDSnet::Lessidentify::PCORnet_CDM;
  my $less = PEDSnet::Lessidentify::PCORnet_CDM->new(
     preserve_attributes => [ qw/ raw_dx raw_rx_med_name/ ],
     force_mappings => { remap_label => 'facility_location' },
     ...);

  while (<$dataset>) {
    my $scrubbed = $less->scrub_record($_);
    put_redacted_record($scrubbed);
  }

=head1 DESCRIPTION

This subclass of L<PEDSnet::Lessidentify> is configured operate on
datasets conforming to the PCORnet Common Data Model v3.  In particular, it implements the
following: 

=over 4

=item *

The C<patid> attribute of a record is used as the person ID for
tracking person-specific remappings.

=cut

sub build_person_id_key { 'patid'; }

=item *

The C<birth_date> attribute of a record is uses as the date of
birth. Time is not available.

=cut

sub build_birth_datetime_key { 'birth_date' }

=item *

Several types of less-identification are done by default:

=over 4

=item *

The values of attributes with names ending in C<id> are remapped.

=item *

The values of attributes with names ending in C<_date> are date-shifted.

=item *

The values of attributes with names ending in C<_time> are
datetime-shifted.

=item *

Values identifying sites, lot numbers, and free-text PRO responses are remapped
as labels.

=item *

The values of attributes with names beginning with C<raw_> are
redacted, as are NPI, patient-specific invitation codes, and textual results.

=item *

The values of the C<site> attribute are remapped as labels.

=back

=cut

sub _build__default_mappings {
  my $self = shift;
  my $start = $self->SUPER::_build__default_mappings // {};
  
  return {
    %$start,
    remap_id => [ qr/id$/i ],
    remap_date => [ qr/_date$/i ],
    remap_datetime => [ qr/_time$/i ],
    remap_label => [ 'site', 'facilityid', 'pro_response_text', 'vx_lot_num' ],
	  alias_attributes => { providerid => [ 'medadmin_providerid',
						'obsgen_providerid',
						'obsclin_providerid',
						'rx_providerid',
						'vx_providerid' ] },
    redact_value => [ qr/^raw_|^trial_invite_code$|^provider_npi$|result_text$|zip9$/i ],
  };
}

no warnings 'void';
'The kids are alright';


__END__

=back

Please see the documentation for L<PEDSnet::Lessidentify> for
information on how to use this class.

=head2 EXPORT

None.

=head1 DIAGNOSTICS

Any message produced by an included package.

=head1 BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

=head1 VERSION

version 1.00

=head1 AUTHOR

Charles Bailey <cbail@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia under
the auspices of PEDSnet, 

=cut

