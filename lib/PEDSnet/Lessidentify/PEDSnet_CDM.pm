#!perl

use 5.011;
use strict;
use warnings;

package PEDSnet::Lessidentify::PEDSnet_CDM;

our($VERSION) = '2.00';

use Moo 2;

use PEDSnet::Lessidentify;
extends 'PEDSnet::Lessidentify';


=head1 NAME

PEDSnet::Lessidentify::PEDSnet_CDM - Make a PEDSnet CDM dataset less identifiable

=head1 SYNOPSIS

  use PEDSnet::Lessidentify::PEDSnet_CDM;
  my $less = PEDSnet::Lessidentify::PEDSnet_CDM->new(
     preserve_attributes => [ qw/value_source_value modifier_source_value/ ],
     force_mappings => { remap_label => 'value_as_string' },
     ...);

  while (<$dataset>) {
    my $scrubbed = $less->scrub_record($_);
    put_redacted_record($scrubbed);
  }

=head1 DESCRIPTION

This subclass of L<PEDSnet::Lessidentify> is configured operate on
datasets conforming to the PEDSnet Common Data Model v2.6 or later, or by
extension the OMOP/OHDSI Common Data Model.  In particular, it
implements the following:

=over 4

=item *

The C<person_id> attribute of a record is used as the person ID for
tracking person-specific remappings.

=cut

sub build_person_id_key { 'person_id'; }

=item *

The C<birth_datetime> attribute of a record is used as the datetime of
birth. 

=cut

sub build_birth_datetime_key { 'birth_datetime' }

=item *

Several types of less-identification are done by default:

=over 4

=item *

The values of attributes with names ending in C<_id> are remapped,
except if the attribute ends in C<_concept_id>.  In addition, the
C<npi> and C<dea> attributes are remapped.

=item *

The values of attributes with names ending in C<_date> are date-shifted.

=item *

The values of attributes with names ending in C<_time> or
C<_datetime>, as well as C<time_of_birth> for historical reasons, are
datetime-shifted.

=item *

The values of attributes with names ending in C<_source_value>, as
well as C<provider_name> are redacted.

=item *

The values of the C<site>, C<zip>, C<address_1>, C<address_2>,
C<city> and C<county> attributes are remapped as labels.

=back

=cut

sub _build__default_mappings {
  my $self = shift;
  my $start = $self->SUPER::_build__default_mappings // {};

  return {
    %$start,
    remap_id => [ qr/(?<!_concept)_id$|^npi$|^dea$/i ],
    remap_date => [ qr/_date$/i ],
    remap_datetime => [ qr/^time_of_birth$|_time$|_datetime$/i ],
    remap_label => [ qw/ site zip address_1 address_2 city county / ],
    redact_value => [ qr/_source_value$|^provider_name$|^care_site_name$|^sig$|^plan_name$/i ],
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

