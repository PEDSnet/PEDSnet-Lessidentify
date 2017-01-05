#!perl

use 5.011;
use strict;
use warnings;

package PEDSnet::Lessidentify::PEDSnet_CDM;

our($VERSION) = '0.01';

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
datasets conforming to the PEDSnet Common Data Model, or by extension
the OMOP/OHDSI Common Data Model.  In particular, it implements the
following: 

=over 4

=item *

The C<person_id> attribute of a record is used as the person ID for
tracking person-specific remappings.

=cut

sub build_person_id_key { 'person_id'; }

=item *

Several types of less-identification are done by default:

=over 4

=item *

The values of attributes with names ending in C<_id> are remapped,
except if the attribute ends in C<_concept_id>.

=item *

The values of attributes with names ending in C<_date> are date-shifted.

=item *

The values of attributes with names ending in C<_time>, as well as
C<time_of_birth>, are datetime-shifted.

=item *

The values of attributes with names ending in C<_source_value> are redacted.

=item *

The values of the C<site> attribute are remapped as labels.

=back

=cut

sub _build__default_mappings {
  my $self = shift;
  my $start = $self->SUPER::_build__default_mappings // {};
  
  {
    remap_id => [ qr/(?<!_concept)_id$/i ],
    remap_date => [ qr/_date$/i ],
    remap_datetime => [ qr/^time_of_birth$|_time$/i ],
    remap_label => [ 'site' ],
    redact_value => [ qr/_source_value$/i ],
    %$start
  };
}

1;

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

version 0.01

=head1 AUTHOR

Charles Bailey <cbail@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia under
the auspices of PEDSnet, 

=cut

