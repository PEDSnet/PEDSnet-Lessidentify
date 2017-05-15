# NAME

PEDSnet::Lessidentify - Make it harder to identifiy individuals in a dataset

# SYNOPSIS

    use PEDSnet::Lessidentify;
    my $less = PEDSnet::Lessidentify->new(
       preserve_attributes => [ qw/value_source_value modifier_source_value/ ],
       force_mappings => { remap_label => 'value_as_string' },
       ...);

    while (<$dataset>) {
      my $scrubbed = $less->scrub_record($_);
      put_redacted_record($scrubbed);
    }

# DESCRIPTION

Minimizing the risk to privacy of persons represented in clinical
datasets is a constant and complex problem.  The United States' Health
Insurance Portability and Accountability Act
([HIPAA](https://www.hhs.gov/hipaa/index.html)) and subsequent
additions ground a [Privacy
Rule](https://www.hhs.gov/hipaa/for-professionals/privacy/index.html)
that sets out common-sense principles, such as using the minimum data
necessary to accomplish a task, as well as specific methods, such as
the [Safe Harbor
method](https://www.hhs.gov/hipaa/for-professionals/privacy/special-topics/de-identification/index.html#safeharborguidance),
to reduce risk that individuals' privacy will be compromised by a user
identifying a person in the dataset.  The Safe Harbor method
recognizes that risk of identification is entailed by both data that
are intentionally unique to an indivdual (e.g. medical record numbers)
and by data that can create circumstances that make reidentification
easier (e.g. dates of birth).  It attempts to strike a balance between
risk reduction and procedures that are consistent and easy to
implement. 

["PEDSnet::Lessidentify"](#pedsnet-lessidentify) takes a similar approach to reducing
identifiability.  We do not refer to the process as
"de-identification" because it does not eliminate the risk of
reidentification, particularly by a reader with outside knowledge of
the data types in the dataset (e.g. direct access to the electronic
source data from which the dataset was derived).  With appropriate
configuration, ["PEDSnet::LEssidentify"](#pedsnet-lessidentify) will do several things:

- Replace values of designated  fields in the data.  The
replacement for a given value is arbitrary, but will be the
same each time that value is encountered, so referential
integrity of keys is maintained.
- Redact values.  This is most useful for string values that
may contain hard-to-find identifiers.  By default, redaction deletes
the value entirely, replacing it with `undef`.
- Shift dates and datetimes.  An arbitrary offset within a year-long
window is generated for each person encountered in the data; this
offset is guaranteed to be at least 1 day long, and for time fields
need not be an integral number of days. Once an offset is generated,
the same offset is used for all date and datetime values associated
with that person, insuring that intervals are preserved.

For additional details, see the documentation for methods below.

What [PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) does not do is provide any guarantee of
k-anonymity (other than the trivial k == 1) or similar strong
anonymization.  It is simply a tool to reduce the impact of the most
likely sources of reidentification.

## ATTRIBUTES

Several attributes allow one to configure the process of
less-identification (a.k.a. scrubbing) of records: 

### What to scrub

[PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) operates by identifying specific attributes
of each record (think columns in a table) and mapping them to new,
presumably less identifiable, values (described below).  However,
[PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) itself has no preconceptions about what to
scrub.  Typically, you will use a subclass that provides some default
rules for scrubbing, but if not, or if you need to change those
defaults, you may find these attributes following useful.

- redact\_attributes

    A reference to an array whose elements specify attribute **names** that
    should be unconditionally redacted when a record is scrubbed. Each
    element is used as a smartmatching target against the attribute names
    of a record being scrubbed, and if an element matches, the value is
    replaced with the return value of ["redact\_value"](#redact_value).  No further
    processing of that attribute is done.

    A match here takes precedence over both ["preserve\_attributes"](#preserve_attributes) and
    ["force\_mappings"](#force_mappings). 

- preserve\_attributes

    A reference to an array whose elements specify attribute **names**
    whose values should be preserved unchanged when a record is
    scrubbed. Each element is used as a smartmatching target against the
    attribute names of a record being scrubbed, and if an element
    matches, no further processing of that attribute is done.

    A match here takes precedence over ["force\_mappings"](#force_mappings), but not
    ["redact\_attributes"](#redact_attributes).

- force\_mappings

    This attribute provides a way to override ["scrub\_record"](#scrub_record)'s default
    logic for deciding how to redact attributes in a record being
    scrubbed. If present, it must be a hash reference, where the keys are
    names of **methods** to be applied to portions of the record being
    scrubbed.  The corresponding values are used as smartmatch targets,
    and if a value matches the **name** of an attribute in the record being
    scrubbed, the indicated method is applied to that attribute's value.

    This sounds fairly complicated, but it lets you be flexible in
    directing particular attributes to redaction methods by saying things
    like 

        { remap_label => [ qr/source_value$/, 'value_as_string' ],
          remap_datetime => 'time_of_event',
          remap_id => \%my_id_names }

## Identifiers

When called, ["remap\_id"](#remap_id) and ["remap\_label"](#remap_label) replace values flagged
as potential reidentification risks with "intelligence-free"
numbers. These numbers are semi-sequential, with some shuffling
introduced to make it more difficult to deduce the sequence of
original values.  The details of this process can be adjusted by a few
attributes, but be sure you understand the tradeoffs if you make
changes. 

- remap\_base

    Specifies the numeric value from which to start assigning replacement
    values in ["remap\_id"](#remap_id).

    If you have turned on ["remap\_per\_attribute\_blocks"](#remap_per_attribute_blocks), you may optionally
    pass a hash reference to the constructor, each key is taken as
    an attribute name, and the corresponding value is used to start
    replacements for values of that attribute in the data.  If you pass an
    integer, that number is used as the base for all reassignments (the
    resulting ["remap\_base"](#remap_base) value is a hash reference with one key named
    `all`.

    I you have not turned on ["remap\_per\_attribute\_blocks"](#remap_per_attribute_blocks), you may pass
    to the constructor either an integer or a hash reference with a single
    key, `all`, associated with the desired value.

- remap\_block\_size

    Instead of assigning replacement values strictly in sequence,
    ["remap\_id"](#remap_id) draws randomly from a block of values, then moves on to
    the next block when the current one is exhausted.  This attribute
    determines how large the blocks are.  Larger blocks take up extra
    working space, but make it harder for a downstream user to deduce the
    order of identifiers in the original data.

    Like ["remap\_base"](#remap_base), you may pass either an integer or a hash
    reference to the constructor.

- remap\_per\_attribute\_blocks

    If set to a true value, causes separate blocks of potential
    replacement values to be maintained for each attribute being
    remapped. Otherwise, replacements are drawn from the same block for
    all remappings.

    The common-block approach works well in the general case, but if you
    set per-attribute values for ["remap\_base"](#remap_base) or [remap\_block\_size](https://metacpan.org/pod/remap_block_size),
    you probably want to turn on per-attribute blocks as well.

### Dates and times

Because intervals between events are frequently important components
of analyses, [PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) treats them differently from
other potential identifiers.  Dates and times are shifted by an amount
that differs for each person, but remains the same for all dates
related to any individual, so that intervals are preserved.  

- person\_id\_key

    Attribute name used to look up person identifier in records, in order
    to maintain a consistent per-person shift.

    There is no default for this value, so you generally need to set it
    for date/time shifts to work properly.  If you're using a subclass of
    [PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify), there's a good chance the subclass sets it
    for you.

- datetime\_window\_days

    This attribute specifies the length (in days) of the window within
    which a date is shifted.

    It defaults to 366, but you may want to choose a narrower window if
    you need to preserve more granular seasonal information, for
    instance. Of course, the shorter the window, the better the chance
    someone can reverse engineer the original date by comparing all the
    alternatives to any external information they may have.  Caveat utor.

- before\_date\_threshold
- after\_date\_threshold

    Emit a warning message if a date(time) in the input is shifted to a
    point earlier than [before\_date\_threshold](https://metacpan.org/pod/before_date_threshold) or later than
    [after\_date\_threshold](https://metacpan.org/pod/after_date_threshold).

    There is no default; if you want boundary warnings, you need to say
    so. 

- date\_threshold\_action

    Determines what to do if a date is encountered outside the range
    between ["before\_date\_threshold"](#before_date_threshold) and ["after\_date\_threshold"](#after_date_threshold).  Three
    options are available:

    - none

        Do nothing.  It's as if the thresholds weren't set.

    - warn

        Emit a warning.

    - retry

        This is a little bit complicated.  If the out-of-threshold date is
        encountered on the **first** attempt to shift a date for that person,
        the offset is recomputed to place the shifted date between the
        thresholds.  If it is encountered on a **subsequent** attempt to shift
        a date, behaves like `warn`, since presumably in-threshold shifted
        dates for that person already exist.

        Defaults to [retry](https://metacpan.org/pod/retry).

- datetime\_to\_age

    If this is set, date/time values are converted to intervals from the
    time of birth (ages), at the granularity specified by
    [datetime\_to\_age](https://metacpan.org/pod/datetime_to_age)'s values.  Valid options are `day`, `month`, or
    `year`. 

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

- birth\_datetime\_key

    Attribute name used to look up a person's date or date/time in
    records, if date/times are being remapped to ages.

    There is no default for this value, so you generally need to set it
    for date/time to age mapping to work properly.  If you're using a
    subclass of [PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify), the subclass may have set it
    for you.

## METHODS

The following methods perform the actual work of scrubbing:

- remap\_id($record, $key)

    Return a numeric substitute value for the contents of _$record->{$key}_.  In list context, returns the original value,
    followed by the substitute.  If the original value is `undef`, then
    `undef` is returned.

    For a given value of _$record->{$key}_, the same substitute will
    be returned on every call.  The first time a new value is seen, a new
    substitute will be generated, and is guaranteed to be unique across
    values of the _$key_ attribute.

- remap\_label($rec, $key)

    Behaves similarly to ["remap\_id"](#remap_id), except that the substitute value is
    a string with _$key_`_` prepended to the number generated by ["remap\_id"](#remap_id).

- remap\_date( $record, $key \[, $options \] )
- remap\_datetime\_always( $record, $key \[, $options \] )
- remap\_datetime( $record, $key \[, $options \] )

    Shift the date or datetime contained in the _$record->{$key}_,
    using a stable person-specific offset.  If an appropriate offset does
    not yet exist, a new one is generated.  The value must be one of
    `undef`, a [DateTime](https://metacpan.org/pod/DateTime), or an ISO-8601 format date(time).

    Typically, the offset is selected using person ID in _$record_
    (cf. ["person\_id\_key).  However, you may specify an alternate person
    ID with which to determine the offset in
    _$options_`<-`{person\_id}"](#person_id_key-however-you-may-specify-an-alternate-person-id-with-which-to-determine-the-offset-in-options-person_id)>.  This may be useful if _$record_ does
    not contain a person ID, but in typical circumstances is not needed,
    and mismatch between the contents of _$record_ and
    _$options_`<-`{person\_id}>> may yield inconsistent results.

    Returns the shifted date or datetime in scalar context, or the
    original value followed by the shifted value in list context.  If the
    original was a [DateTime](https://metacpan.org/pod/DateTime), returns a datetime, otherwise returns a
    string in ISO-8601 format (less time if the input was a date only). In
    either case, ["remap\_datetime\_always"](#remap_datetime_always) will always return a
    value with date and time, and ["remap\_date"](#remap_date) will will always return
    a date only.

    As a special case, because it's common for data to contain datetime
    strings with the time component defaulted to `00:00:00` when the
    source data represented only the date, ["remap\_datetime"](#remap_datetime) looks at the
    time component of the input.  If it's `00:00:00`, then [remap\_date](https://metacpan.org/pod/remap_date)
    is called (and `00:00:00` added to the return value if the input was
    an ISO-8601 string).  Otherwise, ["remap\_datetime\_always"](#remap_datetime_always) is
    called. This reduced the chance that someone can reverse engineer the
    time portion of an offset by knowing that the input value was really a
    date.  The tradeoff is that input values that were true datetimes but
    happened to occur exactly at midnight will have a different offset
    than values that occurred at non-midnight times.  If that's a problem,
    use ["remap\_datetime\_always"](#remap_datetime_always).

- redact\_value($record, $key)

    Redact the value in _$record->{$key}_, and return the redacted
    value.  The default implementation simply returns `undef` for all
    input; subclasses may elect to preserve portions of records with known
    formats.

- scrub\_record($record)

    Examine the keys in the hash reference _$record_, and operate on the
    corresponding values as specified by the object's configuration (both
    package defaults and object attributes described above).  If a given
    key does not match any configuration directive, the corresponding
    value is passed through unchanged.

    Returns a new hash reference containing the less-identified data; the
    contents of _$record_ itself are unchanged.

- save\_maps($path \[, $opts \])

    Serialize the current less-identification state of the object as JSON
    and write it to _$path_. If _$path_ is a reference, it will be
    interpreted as a filehandle.  If it's not a reference, it will be
    interpreted as the name of a file to which to write the data.

    **N.B. The serialized data is a crosswalk between original and
    scrubbed data, and therefore allows restoration of the original data.**
    If you do save state, be sure to take appropriate precautions.

    Because the goal is to create a readable representation, only mapping
    information is saved.  Other aspects of the object, such as criteria
    for matching data attributes to scrubbing methods, is not.  If your
    goal is to freeze the entire state of the object, consider using a
    less readable but more versatile serializer such as [Storable](https://metacpan.org/pod/Storable).

    If present, _$opts_ must be a hash reference.  If the key
    `json_options` is present, the associated value will be passed to
    ["new" in JSON::MaybeXS](https://metacpan.org/pod/JSON::MaybeXS#new) to set formatting of the JSON.

    Returns $path if successful, and raises an exception if an error is
    encountered.

- load\_maps($path \[, $opts \])

    Read JSON-serialized less-identification state from _$path_ and
    replace current state of the object with the result.  If _$path_ is a
    reference, it will be interpreted as a filehandle, and the serialized
    data will be read from it.  If it's not a reference, it will be
    interpreted as the name of a file from which to read the data.

    If present, _$opts_ must be a hash reference.  If the key
    `json_options` is present, the associated value will be passed to
    ["new" in JSON::MaybeXS](https://metacpan.org/pod/JSON::MaybeXS#new) to set formatting of the JSON.

    Returns the caling object if successful, and raises an exception if an
    error is encountered reading the saved state.

## SUBCLASSING

By default, [PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) doesn't do much; it's there to
provide tools.  You can construct a working scrubber by setting
attributes appropriately at object construction time, of course.  But
if you anticipate having to deal with particular kinds of data
repeatedly, it may be useful to wrap the boilerplate up in a subclass.

In addition to overriding any of the mapping methods in
[PEDSnet::Lessidentify](https://metacpan.org/pod/PEDSnet::Lessidentify) or adding new ones, you'll likely want to
address two things:

- build\_person\_id\_key

    This builder sets the **name** of the attribute containing a person ID
    in records being less-identified.  Since there's no default, you'll
    probably want to override this builder.

- \_default\_mappings

    This attribute specifies the package default mappings, in the same
    fashion as ["force\_mappings"](#force_mappings). It is consulted if no match for a given
    attribute is found in ["redact\_attributes"](#redact_attributes), ["preserve\_attributes"](#preserve_attributes), or
    ["force\_mappings"](#force_mappings).

    Although there's nothing ["\_default\_mappings"](#_default_mappings) does that can't be
    accomplished with ["force\_mappings"](#force_mappings), as the name implies, this
    private attribute is intended to let you define standard behaviors for
    a subclass, without interfering with the user's ability to override
    them.

You also have the option of overriding builders for public attributes,
just like any other method, should you want to influence configuration
defaults that way.  And, of course, you may want to override or extend
the set of mapping methods documented above.  There are also some
internal knobs your subclass can tweak to adjust ID mapping, but since
this involves some detailed understanding of how ID mapping is done,
the reader is referred to the source code for further documentation.

## EXPORT

None.

# DIAGNOSTICS

Any message produced by an included package, as well as

- **Date parsing failure** (F)

    You passed a string to one of the date(time)-shifting functions that
    didn't look like a date or time, as understood by
    ["parse\_date" in Rose::DateTime::Util](https://metacpan.org/pod/Rose::DateTime::Util#parse_date). 

# BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

# VERSION

version 1.00

# AUTHOR

Charles Bailey <cbail@cpan.org>

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia as
part of [PCORI](http://www.pcori.org)-funded work in the
[PEDSnet](http://www.pedsnet.org) Data Coordinating Center.
