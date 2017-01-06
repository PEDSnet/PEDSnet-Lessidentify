#!perl

use 5.011;
use strict;
use warnings;

package PEDSnet::Lessidentify;

our($VERSION) = '0.01';

use Carp qw(croak);

use Moo 2;
use experimental 'smartmatch';
use Types::Standard qw/ Any Maybe Str ArrayRef HashRef /;

use DateTime;
use Math::Random::Secure qw(rand);
use Rose::DateTime::Util qw(parse_date);

with 'MooX::Role::Chatty';

=head1 NAME

PEDSnet::Lessidentify - Make it harder to identifiy individuals in a dataset

=head1 SYNOPSIS

  use PEDSnet::Lessidentify;
  my $less = PEDSnet::Lessidentify->new(
     preserve_attributes => [ qw/value_source_value modifier_source_value/ ],
     force_mappings => { remap_label => 'value_as_string' },
     ...);

  while (<$dataset>) {
    my $scrubbed = $less->scrub_record($_);
    put_redacted_record($scrubbed);
  }

=head1 DESCRIPTION

Minimizing the risk to privacy of persons represented in clinical
datasets is a constant and complex problem.  The United States' Health
Insurance Portability and Accountability Act
(L<HIPAA|https://www.hhs.gov/hipaa/index.html>) and subsequent
additions ground a L<Privacy
Rule|https://www.hhs.gov/hipaa/for-professionals/privacy/index.html>
that sets out common-sense principles, such as using the minimum data
necessary to accomplish a task, as well as specific methods, such as
the L<Safe Harbor
method|https://www.hhs.gov/hipaa/for-professionals/privacy/special-topics/de-identification/index.html#safeharborguidance>,
to reduce risk that individuals' privacy will be compromised by a user
identifying a person in the dataset.  The Safe Harbor method
recognizes that risk of identification is entailed by both data that
are intentionally unique to an indivdual (e.g. medical record numbers)
and by data that can create circumstances that make reidentification
easier (e.g. dates of birth).  It attempts to strike a balance between
risk reduction and procedures that are consistent and easy to
implement. 

L</PEDSnet::Lessidentify> takes a similar approach to reducing
identifiability.  We do not refer to the process as
"de-identification" because it does not eliminate the risk of
reidentification, particularly by a reader with outside knowledge of
the data types in the dataset (e.g. direct access to the electronic
source data from which the dataset was derived).  With appropriate
configuration, L</PEDSnet::LEssidentify> will do several things:

=over 4

=item *

Replace values of designated  fields in the data.  The
replacement for a given value is arbitrary, but will be the
same each time that value is encountered, so referential
integrity of keys is maintained.

=item *

Redact values.  This is most useful for string values that
may contain hard-to-find identifiers.  By default, redaction deletes
the value entirely, replacing it with C<undef>.

=item *

Shift dates and datetimes.  An arbitrary offset within a year-long
window is generated for each person encountered in the data; this
offset is guaranteed to be at least 1 day long, and for time fields
need not be an integral number of days. Once an offset is generated,
the same offset is used for all date and datetime values associated
with that person, insuring that intervals are preserved.

=back

For additional details, see the documentation for methods below.

What L<PEDSnet::Lessidentify> does not do is provide any guarantee of
k-anonymity (other than the trivial k == 1) or similar strong
anonymization.  It is simply a tool to reduce the impact of the most
likely sources of reidentification.

=head2 ATTRIBUTES

Several attributes allow one to configure the process of
less-identification (a.k.a. scrubbing) of records: 

=over 4

=cut

## Internal attributes. Ok for use by subclasses; for details on
## usage, UTSL.

# Mapping of designated values to replacements.
has '_id_map' =>
  ( isa => HashRef, is => 'ro', init_arg => undef, default => sub { {} } );

# Internal serial counters used to generate replacement values.
has '_id_counters' =>
  ( isa => HashRef, is => 'ro', init_arg => undef, default => sub { {} } );

# Datetime offsets for individual persons
has '_datetime_map' =>
  ( isa => HashRef, is => 'ro', init_arg => undef, default => sub { {} } );

# =item _default_mappings
#
# See pod later in this file.
#
has '_default_mappings' =>
  ( isa => Maybe[HashRef], is => 'ro', required => 0, lazy => 1,
    builder => '_build__default_mappings' );

sub _build__default_mappings {}

=item person_id_key

Attribute name used to look up patient identifier in records.  There
is no default for this value.

=cut

has 'person_id_key' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_person_id_key' );

sub build_person_id_key {}

=item redact_attributes

A reference to an array whose elements specify attribute B<names> that
should be unconditionally redacted when a record is scrubbed. Each
element is used as a smartmatching target against the attribute names
of a record being scrubbed, and if an element matches, the value is
replaced with the return value of L</redact_value>.  No further
processing of that attribute is done.

A match here takes precedence over both L</preserve_attributes> and
L</force_mappings>. 

=cut

has 'redact_attributes' =>
  ( isa => Maybe[ArrayRef], is => 'ro', required => 0, lazy => 1,
    builder => 'build_redact_attributes'
  );

sub build_redact_attributes {}

=item preserve_attributes

A reference to an array whose elements specify attribute B<names>
whose values should be preserved unchanged when a record is
scrubbed. Each element is used as a smartmatching target against the
attribute names of a record being scrubbed, and if an element
matches, no further processing of that attribute is done.

A match here takes precedence over L</force_mappings>, but not
L</redact_attributes>.

=cut

has 'preserve_attributes' =>
  ( isa => Maybe[ArrayRef], is => 'ro', required => 0, lazy => 1,
    builder => 'build_preserve_attributes'
  );

sub build_preserve_attributes {}

=item force_mappings

This attribute provides a way to override L</scrub_record>'s default
logic for deciding how to redact attributes in a record being
scrubbed. If present, it must be a hash reference, where the keys are
names of B<methods> to be applied to portions of the record being
scrubbed.  The corresponding values are used as smartmatch targets,
and if a value matches the B<name> of an attribute in the record being
scrubbed, the indicated method is applied to that attribute's value.

This sounds fairly complicated, but it lets you be flexible in
directing particular attributes to redaction methods by saying things
like 

  { remap_label => [ qr/source_value$/, 'value_as_string' ],
    remap_datetime => 'time_of_event',
    remap_id => \%my_id_names }

=cut

has 'force_mappings' =>
  ( isa => Maybe[HashRef], is => 'ro', required => 0, lazy => 1,
    builder => 'build_force_mappings' );

sub build_force_mappings {}


=back

=head2 METHODS

The following methods perform the actual work of scrubbing:

=over 4

=item remap_id($record, $key)

Return a numeric substitute value for the contents of I<<
$record->{$key} >>.  In list context, returns the original value,
followed by the substitute.  If the original value is C<undef>, then
C<undef> is returned.

For a given value of I<< $record->{$key} >>, the same substitute will
be returned on every call.  The first time a new value is seen, a new
substitute will be generated, and is guaranteed to be unique across
values of the I<$key> attribute.

=cut

sub remap_id {
  my($self, $rec, $key) = @_;
  my $orig = $rec->{$key};
  return unless defined $orig;

  my $map = $self->_id_map;

  $map->{$key} //= {};
  unless ($map->{$key}->{$orig}) {
    my $ctr = $self->_id_counters;
    $ctr->{$key} //= 1;
    $map->{$key}->{$orig} = $ctr->{$key}++;
  }

  $self->remark({ level => 2,
		  message => "$key value $orig remapped to " .
		  "$map->{$key}->{$orig}\n"});

  return  ($orig, $map->{$key}->{$orig}) if wantarray;
  return $map->{$key}->{$orig};
  
}

=item remap_label($rec, $key)

Behaves similarly to L</remap_id>, except that the substitute value is
a string with I<$key>C<_> prepended to the number generated by L</remap_id>.

=cut

sub remap_label {
 my($self, $rec, $key) = @_; 
 my $new = sprintf('%s_%d', $key, scalar $self->remap_id($rec, $key));

 return ($rec->{$key}, $new) if wantarray;
 return $new;
 
}


# =item _new_time_offset( $person_id )
#
# Create new person-specific date/datetime offset, +/- 183 days.  The
# offset is guaranteed to be at least one day.
#
# Returns a DateTime::Duration object representing that offset.

sub _new_time_offset {
  my($self, $person_id) = @_;
  my $offset = rand(366) - 183;
  $offset += ($offset < 0 ? -1 : 1) if abs($offset) < 1;
  my $days = int($offset);
  my $min_frac =  ($offset - $days) * 60 * 24;
  my $whole_min = int($min_frac);
  my $off =
    $self->_datetime_map->{$person_id} = DateTime::Duration->
    new( days => $days, minutes => $whole_min,
	 seconds => int( ($min_frac - $whole_min) * 60 ) );

  if ($self->verbose >= 3) {
    my $deltas = $off->deltas;
    $self->remark("Generated new offset for $person_id: " .
		  join(', ', map { '$_ => ' . $deltas->{$_} }
		       qw/ days minutes seconds/));
  }
  $off;
}

=item remap_date( $record, $key [, $options ] )

=item remap_datetime_always( $record, $key [, $options ] )

=item remap_datetime( $record, $key [, $options ] )

Shift the date or datetime contained in the I<< $record->{$key} >>,
using a stable person-specific offset.  If an appropriate offset does
not yet exist, a new one is generated.  The value must be one of
C<undef>, a L<DateTime>, or an ISO-8601 format date(time).

Typically, the offset is selected using person ID in I<$record>
(cf. L</person_id_key).  However, you may specify an alternate person
ID with which to determine the offset in
I<$options>C<<->{person_id}>>.  This may be useful if I<$record> does
not contain a person ID, but in typical circumstances is not needed,
and mismatch between the contents of I<$record> and
I<$options>C<<->{person_id}>> may yield inconsistent results.

Returns the shifted date or datetime in scalar context, or the
original value followed by the shifted value in list context.  If the
original was a L<DateTime>, returns a datetime, otherwise returns a
string in ISO-8601 format (less time if the input was a date only). In
either case, L</remap_datetime_always> will always return a
value with date and time, and L</remap_date> will will always return
a date only.

As a special case, because it's common for data to contain datetime
strings with the time component defaulted to C<00:00:00> when the
source data represented only the date, L</remap_datetime> looks at the
time component of the input.  If it's C<00:00:00>, then L<remap_date>
is called (and C<00:00:00> added to the return value if the input was
an ISO-8601 string).  Otherwise, L</remap_datetime_always> is
called. This reduced the chance that someone can reverse engineer the
time portion of an offset by knowing that the input value was really a
date.  The tradeoff is that input values that were true datetimes but
happened to occur exactly at midnight will have a different offset
than values that occurred at non-midnight times.  If that's a problem,
use L</remap_datetime_always>.

=cut

sub _do_remap_datetime {
  my($self, $rec, $key, $opts, $flags) = @_;
  $opts //= {};
  $flags //= {};
  my $pid = $opts->{person_id} // $rec->{ $self->person_id_key };
  my $orig = $rec->{$key};
  my $map = $self->_datetime_map;
  my $new;
  
  return unless defined $pid and defined $orig and length $orig;
  $orig = parse_date($orig) unless ref $orig;
  croak "Date parsing failure for $pid: $rec->{$key}"
    unless $orig;
  
  $self->_new_time_offset($pid) unless exists $map->{$pid};

  $new = $orig + $map->{$pid};

  if ($self->verbose >= 2) {
    my $offset = '';
    if ($self->verbose > 2) {
      my $deltas = $map->{$pid}->deltas;
      $offset = '(offset ' .
	join(', ', map { '$_ => ' . $deltas->{$_} }
	     $flags->{date_only} ? ('days') : (qw/ days minutes seconds/ )) . ')';
    }
    $self->remark("Date(time) $orig mapped to $new$offset for person $pid\n");
  }

  if ($flags->{date_only}) {
    $new = ref($rec->{$key}) ? $new->truncate(to => 'day') : $new->ymd;
  }
  elsif (not ref $rec->{$key}) {
    $new = $new->iso8601;
    my($spacer) = $rec->{$key} =~ /\d+(.)\d+:/;
    $new =~ s/T/$spacer/ if defined $spacer;
  }

  return ($rec->{$key}, $new) if wantarray;
  return $new;
  
}

sub remap_date {
  my($self, $rec, $key, $opts) = @_;
  $self->_do_remap_datetime($rec, $key, $opts, { date_only => 1 });
}
sub remap_datetime_always {
  my($self, $rec, $key, $opts) = @_;
  $self->_do_remap_datetime($rec, $key, $opts, { });
}
sub remap_datetime {
  my($self, $rec, $key, $opts) = @_;

  if ($rec->{$key} =~ /(.)00:00:00$/) {
    my $sep = $1;
    my $new = $self->remap_date($rec, $key, $opts);
    return  ref($new) ? $new : ($new . $sep . '00:00:00');
  }
  else {
    return $self->remap_datetime_always($rec, $key, $opts);
  }
}

=item redact_value($record, $key)

Redact the value in I<< $record->{$key} >>, and return the redacted
value.  The default implementation simply returns C<undef> for all
input; subclasses may elect to preserve portions of records with known
formats.

=cut

sub redact_value { return undef; }

=item scrub_record($record)

Examine the keys in the hash reference I<$record>, and operate on the
corresponding values as specified by the object's configuration (both
package defaults and object attributes described above).  If a given
key does not match any configuration directive, the corresponding
value is passed through unchanged.

Returns a new hash reference containing the less-identified data; the
contents of I<$record> itself are unchanged.

=cut

sub scrub_record {
  my($self, $rec, $opts) = @_;
  $opts //= {};
  my $preserve = $self->preserve_attributes;
  my $redact = $self->redact_attributes;
  my $force = $self->force_mappings // {};
  my $def_map = $self->_default_mappings;
  my %new = %$rec;

  foreach my $k (keys %new) {
    $new{$k} = $self->redact_value($rec, $k), next if $k ~~ $redact;
    next if $k ~~ $preserve;

    for ($k) {
      if ( keys %$force and $k ~~ [ values %$force ]) {
	foreach my $func (keys %$force) {
	  if ($k ~~ $force->{$func}) {
	    $new{$k} = $self->$func($rec, $k);
	    next;
	  }
	}
      }
      elsif ( keys %$def_map and $k ~~ [ values %$def_map ]) {
	foreach my $func (keys %$def_map) {
	  if ($k ~~ $def_map->{$func}) {
	    $new{$k} = $self->$func($rec, $k);
	    next;
	  }
	}
      }
    }
  }

  \%new;
}

no warnings 'void';
'Less is more';

__END__

=back

=head2 SUBCLASSING

By default, L<PEDSnet::Lessidentify> doesn't do much; it's there to
provide tools.  You can construct a working scrubber by setting
attributes appropriately at object construction time, of course.  But
if you anticipate having to deal with particular kinds of data
repeatedly, it may be useful to wrap the boilerplate up in a subclass.

In addition to overriding any of the mapping methods in
L<PEDSnet::Lessidentify> or adding new ones, you'll likely want to
address two things:

=over 4

=item build_person_id_key

This builder sets the B<name> of the attribute containing a person ID
in records being less-identified.  Since there's no default, you'll
probably want to override this builder.

=item _default_mappings

This attribute specifies the package default mappings, in the same
fashion as L</force_mappings>. It is consulted if no match for a given
attribute is found in L</redact_attributes>, L</preserve_attributes>, or
L</force_mappings>.

Although there's nothing L</_default_mappings> does that can't be
accomplished with L</force_mappings>, as the name implies, this
private attribute is intended to let you define standard behaviors for
a subclass, without interfering with the user's ability to override
them.

=back

You also have the option of overriding builders for public attributes,
just like any other method, should you want to influence configuration
defaults that way.  These include:

=over 4

=item build_redact_attributes

=item build_preserve_attributes

=item build_force_mappings

=back
=head2 EXPORT

None.

=head1 DIAGNOSTICS

Any message produced by an included package, as well as

=over 4

=item B<Date parsing failure> (F)

You passed a string to one of the date(time)-shifting functions that
didn't look like a date or time, as understood by
L<Rose::DateTime::Util/parse_date>. 

=back

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
