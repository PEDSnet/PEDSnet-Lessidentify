#!perl

use 5.011;
use strict;
use warnings;

package PEDSnet::Lessidentify;

our($VERSION) = '1.00';

use Carp qw(croak);

use Moo 2;
use experimental 'smartmatch';
use Types::Standard qw/ Any Maybe Bool Str StrictNum ArrayRef
			HashRef Enum InstanceOf /;

use DateTime;
use Math::Random::Secure qw(rand irand);
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

=for Pod::Coverage build_.+

=cut

## Internal attributes. Ok for use by subclasses; for details on
## usage, UTSL.

# Mapping of designated values to replacements.
has '_id_map' =>
  ( isa => HashRef, is => 'rwp', init_arg => undef, default => sub { {} } );

# Internal serial counters used to generate replacement values.
has '_id_counters' =>
  ( isa => HashRef, is => 'rwp', init_arg => undef, default => sub { {} } );

# Current block(s) of IDs for mapping.  Not saved as state.
has '_id_remap_blocks' =>
  ( isa => HashRef, is => 'ro', init_arg => undef,
    default => sub { { all => [] } } );

# Datetime map for individual persons
# If converting dates to ages, this is the person's base
# date (preferably DOB).  If not converting, it is an offset.
has '_datetime_map' =>
  ( isa => HashRef, is => 'rwp', init_arg => undef, default => sub { {} } );

# =item _default_mappings
#
# See pod later in this file.
#
has '_default_mappings' =>
  ( isa => Maybe[HashRef], is => 'ro', required => 0, lazy => 1,
    builder => '_build__default_mappings' );

sub _build__default_mappings {}

=head3 What to scrub

L<PEDSnet::Lessidentify> operates by identifying specific attributes
of each record (think columns in a table) and mapping them to new,
presumably less identifiable, values (described below).  However,
L<PEDSnet::Lessidentify> itself has no preconceptions about what to
scrub.  Typically, you will use a subclass that provides some default
rules for scrubbing, but if not, or if you need to change those
defaults, you may find these attributes following useful.

=over 4

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

=head2 Identifiers

When called, L</remap_id> and L</remap_label> replace values flagged
as potential reidentification risks with "intelligence-free"
numbers. These numbers are semi-sequential, with some shuffling
introduced to make it more difficult to deduce the sequence of
original values.  The details of this process can be adjusted by a few
attributes, but be sure you understand the tradeoffs if you make
changes. 

=over 4

=item remap_base

Specifies the numeric value from which to start assigning replacement
values in L</remap_id>.

If you have turned on L</remap_per_attribute_blocks>, you may optionally
pass a hash reference to the constructor, each key is taken as
an attribute name, and the corresponding value is used to start
replacements for values of that attribute in the data.  If you pass an
integer, that number is used as the base for all reassignments (the
resulting L</remap_base> value is a hash reference with one key named
C<all>.

I you have not turned on L</remap_per_attribute_blocks>, you may pass
to the constructor either an integer or a hash reference with a single
key, C<all>, associated with the desired value.

=cut

has 'remap_base' =>
  ( isa => HashRef, is => 'rwp', required => 0, lazy => 1,
    coerce => sub { ref $_[0] ? $_[0] : { all => $_[0] }},
    builder => 'build_remap_base' );

sub build_remap_base { { all => irand(1000) } }

=item remap_block_size

Instead of assigning replacement values strictly in sequence,
L</remap_id> draws randomly from a block of values, then moves on to
the next block when the current one is exhausted.  This attribute
determines how large the blocks are.  Larger blocks take up extra
working space, but make it harder for a downstream user to deduce the
order of identifiers in the original data.

Like L</remap_base>, you may pass either an integer or a hash
reference to the constructor.

=cut

has 'remap_block_size' =>
  ( isa => HashRef, is => 'rwp', required => 0, lazy => 1,
    coerce => sub { ref $_[0] ? $_[0] : { all => $_[0] }},
    builder => 'build_remap_block_size' );

sub build_remap_block_size { { all => 1000 + irand(1000) } }

=item remap_per_attribute_blocks

If set to a true value, causes separate blocks of potential
replacement values to be maintained for each attribute being
remapped. Otherwise, replacements are drawn from the same block for
all remappings.

The common-block approach works well in the general case, but if you
set per-attribute values for L</remap_base> or L<remap_block_size>,
you probably want to turn on per-attribute blocks as well.

=cut

has 'remap_per_attribute_blocks' =>
  ( isa => Bool, is => 'rwp', required => 0, lazy => 1,
    builder => 'build_remap_per_attribute_blocks' );

sub build_remap_per_attribute_blocks { 0 }

=back

=head3 Dates and times

Because intervals between events are frequently important components
of analyses, L<PEDSnet::Lessidentify> treats them differently from
other potential identifiers.  Dates and times are shifted by an amount
that differs for each person, but remains the same for all dates
related to any individual, so that intervals are preserved.  

=over 4

=item person_id_key

Attribute name used to look up person identifier in records, in order
to maintain a consistent per-person shift.

There is no default for this value, so you generally need to set it
for date/time shifts to work properly.  If you're using a subclass of
L<PEDSnet::Lessidentify>, there's a good chance the subclass sets it
for you.

=cut

has 'person_id_key' =>
  ( isa => Str, is => 'rwp', required => 1, lazy => 1,
    builder => 'build_person_id_key' );

sub build_person_id_key {}

=item datetime_window_days

This attribute specifies the length (in days) of the window within
which a date is shifted.

It defaults to 366, but you may want to choose a narrower window if
you need to preserve more granular seasonal information, for
instance. Of course, the shorter the window, the better the chance
someone can reverse engineer the original date by comparing all the
alternatives to any external information they may have.  Caveat utor.

=cut

has 'datetime_window_days' =>
  ( isa => StrictNum, is => 'rwp', required => 0, lazy => 1,
    builder => 'build_datetime_window_days' );

sub build_datetime_window_days { 366 }

=item before_date_threshold

=item after_date_threshold

Emit a warning message if a date(time) in the input is shifted to a
point earlier than L<before_date_threshold> or later than
L<after_date_threshold>.

There is no default; if you want boundary warnings, you need to say
so. 

=cut

has 'before_date_threshold' =>
  ( isa => Maybe[InstanceOf['DateTime']], is => 'rwp', required => 0, lazy => 1,
    coerce => sub { ref $_[0] ? $_[0] : parse_date($_[0]) },
    builder => 'build_before_date_threshold' );

sub build_before_date_threshold {}

has 'after_date_threshold' =>
  ( isa => Maybe[InstanceOf['DateTime']], is => 'rwp', required => 0, lazy => 1,
    coerce => sub { ref $_[0] ? $_[0] : parse_date($_[0]) },
    builder => 'build_after_date_threshold' );

sub build_after_date_threshold {}

=item date_threshold_action

Determines what to do if a date is encountered outside the range
between L</before_date_threshold> and L</after_date_threshold>.  Three
options are available:

=over 4

=item none

Do nothing.  It's as if the thresholds weren't set.

=item warn

Emit a warning.

=item retry

This is a little bit complicated.  If the out-of-threshold date is
encountered on the B<first> attempt to shift a date for that person,
the offset is recomputed to place the shifted date between the
thresholds.  To avoid hanging on pathologic dates, it will only retry
a limited number of times before giving up with a warning.

If it is encountered on a B<subsequent> attempt to shift a date,
behaves like C<warn>, since presumably in-threshold shifted dates for
that person already exist.

Defaults to L<retry>.

=back

=cut

has 'date_threshold_action' =>
  ( isa => Maybe[Enum[qw/ none warn retry / ]], is => 'rwp', lazy => 1,
    builder => 'build_date_threshold_action' );

sub build_date_threshold_action { 'retry' }

=item datetime_to_age

If this is set, date/time values are converted to intervals from the
time of birth (ages), at the granularity specified by
L<datetime_to_age>'s values.  Valid options are C<day>, C<month>, or
C<year>. 

In some cases, using only intervals may reduce reidentification risk
more than using shifted dates.  However, be aware that this
transformation changes the data type of (formerly) date/time
attributes; you may need to make adjustment to downstream applications
to reflect this.

It's also important to realize that in order to get accurate ages, a
person's birth date/time has to be present in the input data before
any other date/times for that person.  If not, the "age"s will be
intervals from some point in time that's likely not meaningful to that
person.

=cut

has 'datetime_to_age' =>
  ( isa => Maybe[Enum[ qw/ days months years / ]], is => 'rwp', lazy => 1,
    builder => 'build_datetime_to_age' );

sub build_datetime_to_age { undef }

=item birth_datetime_key

Attribute name used to look up a person's date or date/time in
records, if date/times are being remapped to ages.

There is no default for this value, so you generally need to set it
for date/time to age mapping to work properly.  If you're using a
subclass of L<PEDSnet::Lessidentify>, the subclass may have set it
for you.

=cut

has 'birth_datetime_key' =>
  ( isa => Maybe[Str], is => 'rwp', required => 0, lazy => 1,
    builder => 'build_birth_datetime_key' );

sub build_birth_datetime_key {}

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

  # If we've already mapped this value, don't generate a new replacement.
  unless ($map->{$key}->{$orig}) {
    my $cb = $self->_id_remap_blocks;
    my($per_attr, $thisblock);

    # If we haven't seen this attribute at all yet, establish from
    # where we're going to get new IDs
    if (not exists $cb->{$key}) {
      $per_attr = $self->remap_per_attribute_blocks;
      $cb->{$key} =  $per_attr ? [] : $cb->{all};
    }
    $thisblock = $cb->{$key};
    
    # If we don't have values in current block to pick from, fill a
    # new one.
    if (not @$thisblock) {
      my $ctr = $self->_id_counters;
      my $bases = $self->remap_base;
      my $sizes = $self->remap_block_size;
      $per_attr //= $self->remap_per_attribute_blocks;
      my $bkey = $per_attr ? $key : 'all';
      my $base = $bases->{$bkey} // $bases->{all};
      my $size = $sizes->{$bkey} // $sizes->{all};
      
      $ctr->{$bkey} //= $base;
      push @$thisblock,
	($ctr->{$bkey} .. $ctr->{$bkey} + $size - 1);
      $ctr->{$bkey} += $size;
    }
    
    # Pick a new ID from the waiting block, insuring it's different
    do {
      $map->{$key}->{$orig} =
	splice( @$thisblock, rand() * scalar(@$thisblock), 1)
    } while $map->{$key}->{$orig} eq $orig;
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
  my $win = $self->datetime_window_days;
  my $offset = rand($win) - $win/2;
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

sub _do_datetime_to_age {
  my($self, $rec, $key, $opts, $flags) = @_;
  $opts //= {};
  $flags //= {};
  my $pid = $opts->{person_id} // $rec->{ $self->person_id_key };
  my $orig = $rec->{$key};
  my $map = $self->_datetime_map;
  my($new, $newstr);
    
  return unless defined $pid and defined $orig and length $orig;
  $orig = parse_date($orig) unless ref $orig;
  croak "Date parsing failure for $pid: $rec->{$key}"
    unless $orig;
  
  unless (exists $map->{$pid}) {
    $map->{$pid} = $opts->{birth_datetime} //
      $rec->{ $self->{birth_datetime_key} } //
      ( DateTime->now - DateTme::Duration->new( years => 100 + irand(50),
						months => irand(12),
						days => irand(30) ) );
  }

  $new = $orig->subtract_datetime( $map->{$pid} );

  if ($self->verbose >=2 or not ref $rec->{$key}) {
    my $newstr = $new->deltas;
    $newstr = $new->{months} + $new->{days} / 30.44;
    $newstr += $new->{minutes} / 1440 + $new->{seconds} / 86400
      unless $flags->{date_only};

    $self->remark("Date(time) $orig mapped to age $newstr for person $pid\n")
      if ($self->verbose >=2);

    $new = $newstr unless ref $rec->{$key};
  }

  return ($rec->{$key}, $new) if wantarray;
  return $new;
}  

sub _do_remap_datetime {
  my($self, $rec, $key, $opts, $flags) = @_;
  $opts //= {};
  $flags //= {};
  my $pid = $opts->{person_id} // $rec->{ $self->person_id_key };
  my $orig = $rec->{$key};
  my $map = $self->_datetime_map;
  my($min, $max, $action) = ($self->before_date_threshold, $self->after_date_threshold,
			    $self->date_threshold_action);
  my $new;
  
  if (not $action or $action eq 'none') { undef $min; undef $max }
  
  return unless defined $pid and defined $orig and length $orig;
  $orig = parse_date($orig) unless ref $orig;
  croak "Date parsing failure for $pid: $rec->{$key}"
    unless $orig;
  
  unless (exists $map->{$pid}) {
    $self->_new_time_offset($pid);

    if (($min || $max) && $action eq 'retry') {
      my $i = 0;

      for ( ; $i++ < 100; $self->_new_time_offset($pid)) {
	my $test = $orig + $map->{$pid};
	next if $min and $test < $min;
	next if $max and $test > $max;
	last;
      }

      if ($i > 100) {
	$self->logger->critical("Can't get offset within date threshold for $pid " .
				"(starting from $orig with bounds of [" .
				($min ? $min : 'undef') . ($max ? $max : 'undef') .'])');
      }
    }
  }

  $new = $orig + $map->{$pid};

  if ($self->verbose >= 2) {
    my $offset = '';
    if ($self->verbose > 2) {
      my $deltas = $map->{$pid}->deltas;
      $offset = '(offset ' .
	join(', ', map { '$_ => ' . $deltas->{$_} }
	     $flags->{date_only} ? ('days') : (qw/ days minutes seconds/ )) . ')';
    }
    $self->remark("Date(time) $orig mapped to $new $offset for person $pid\n");
  }

  $self->logger->warn("Early date warning: remapped $orig to $new for person $pid")
    if $min and $new < $min;
  $self->logger->warn("Late date warning: remapped $orig to $new for person $pid")
    if $max and $new > $max;

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

  if ($self->datetime_to_age) {
    return $self->_do_datetime_to_age($rec, $key, $opts, { date_only => 1 });
  }
  else {
    return $self->_do_remap_datetime($rec, $key, $opts, { date_only => 1 });
  }
}

sub remap_datetime_always {
  my($self, $rec, $key, $opts) = @_;

  if ($self->datetime_to_age) {
    return $self->_do_datetime_to_age($rec, $key, $opts, { });
  }
  else {
    return $self->_do_remap_datetime($rec, $key, $opts, { });
  }
}

sub remap_datetime {
  my($self, $rec, $key, $opts) = @_;

  if ($rec->{$key} =~ /(.)00:00:00$/) {
    my $sep = $1;
    my $new = $self->remap_date($rec, $key, $opts);

    return $new if $self->datetime_to_age or ref $new;
    return $new . $sep . '00:00:00';
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

=item save_maps($path [, $opts ])

Serialize the current less-identification state of the object as JSON
and write it to I<$path>. If I<$path> is a reference, it will be
interpreted as a filehandle.  If it's not a reference, it will be
interpreted as the name of a file to which to write the data.

B<N.B. The serialized data is a crosswalk between original and
scrubbed data, and therefore allows restoration of the original data.>
If you do save state, be sure to take appropriate precautions.

Because the goal is to create a readable representation, only mapping
information is saved.  Other aspects of the object, such as criteria
for matching data attributes to scrubbing methods, is not.  If your
goal is to freeze the entire state of the object, consider using a
less readable but more versatile serializer such as L<Storable>.

If present, I<$opts> must be a hash reference.  If the key
C<json_options> is present, the associated value will be passed to
L<JSON::MaybeXS/new> to set formatting of the JSON.

Returns $path if successful, and raises an exception if an error is
encountered.

=cut

sub save_maps {
  my($self, $path, $opts) = @_;
  $opts //= {};
  
  require JSON::MaybeXS;
  my $json = JSON::MaybeXS->new($opts->{json_options} //
				{ utf8 => 1, pretty => 1 });

  my $dtm = $self->_datetime_map;
  my $state =
    $json->encode({ person_id_key => $self->person_id_key,
		    id_map => $self->_id_map,
		    id_counters => $self->_id_counters,
		    remap_base => $self->remap_base,
		    remap_block_size => $self->remap_block_size,
		    remap_per_attribute_blocks => $self->remap_per_attribute_blocks,
		    datetime_map => { map { $_ => { $dtm->{$_}->deltas } }
				      keys %$dtm },
		    datetime_window_days => $self->datetime_window_days,
		    before_date_threshold => $self->before_date_threshold,
		    after_date_threshold => $self->after_date_threshold,
		    date_threshold_action => $self->date_threshold_action,
		    datetime_to_age => $self->datetime_to_age,
		    birth_datetime_key => $self->birth_datetime_key,
		  });
  my $fh = $path;

  unless (ref $fh) {
    require Path::Tiny;
    $fh = Path::Tiny::path($fh)->openw_raw;
    croak "Failed to open $path: $!" unless $fh;
  }
  my $sts = print $fh $state;
  $sts = $sts && close($fh) unless ref $path;
  $sts or croak "Error writing to $path: $!";

  $path;
}


=item load_maps($path [, $opts ])

Read JSON-serialized less-identification state from I<$path> and
replace current state of the object with the result.  If I<$path> is a
reference, it will be interpreted as a filehandle, and the serialized
data will be read from it.  If it's not a reference, it will be
interpreted as the name of a file from which to read the data.

If present, I<$opts> must be a hash reference.  If the key
C<json_options> is present, the associated value will be passed to
L<JSON::MaybeXS/new> to set formatting of the JSON.

Returns the caling object if successful, and raises an exception if an
error is encountered reading the saved state.

=cut

sub load_maps {
  my($self, $path, $opts) = @_;
  $opts //= {};
  
  require JSON::MaybeXS;
  my $json = JSON::MaybeXS->new($opts->{json_options} //
				{ utf8 => 1 });
  my $fh = $path;
  my($state);

  unless (ref $fh) {
    require Path::Tiny;
    $fh = Path::Tiny::path($fh)->openr_raw;
    croak "Failed to open $opts->{path}: $!" unless $fh;
  }

  $state = join '', <$fh>;

  unless (ref $path) {
    close($fh)
      or croak "Error writing to $opts->{path}: $!";
  }

  $state = $json->decode($state);
  my $dtm = $state->{datetime_map};
  $dtm->{$_} = DateTime::Duration->new( %{ $dtm->{$_} }) for keys %$dtm;

  $self->_set_person_id_key($state->{person_id_key});
  $self->_set__id_map($state->{id_map});
  $self->_set__id_counters($state->{id_counters});
  $self->_set_remap_base($state->{remap_base});
  $self->_set_remap_block_size($state->{remap_block_size});
  $self->_set_remap_per_attribute_blocks($state->{remap_per_attribute_blocks});
  $self->_set__datetime_map($dtm);
  $self->_set_datetime_window_days($state->{datetime_window_days});
  $self->_set_datetime_to_age($state->{datetime_to_age});
  $self->_set_before_date_threshold($state->{before_date_threshold});
  $self->_set_after_date_threshold($state->{after_date_threshold});
  $self->_set_date_threshold_action($state->{date_threshold_action});
  $self->_set_birth_datetime_key($state->{birth_datetime_key});

  $self;
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
defaults that way.  And, of course, you may want to override or extend
the set of mapping methods documented above.  There are also some
internal knobs your subclass can tweak to adjust ID mapping, but since
this involves some detailed understanding of how ID mapping is done,
the reader is referred to the source code for further documentation.

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

version 1.00

=head1 AUTHOR

Charles Bailey <cbail@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia as
part of L<PCORI|http://www.pcori.org>-funded work in the
L<PEDSnet|http://www.pedsnet.org> Data Coordinating Center.

=cut
