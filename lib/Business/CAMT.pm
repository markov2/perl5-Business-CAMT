# This code is part of distribution Business::CAMT.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

# https://www.betaalvereniging.nl/wp-content/uploads/IG-Bank-to-Customer-Statement-CAMT-053-v1-1.pdf

package Business::CAMT;

use strict;
use warnings;
use utf8;

use Log::Report 'business-camt';

use Path::Class         ();
use XML::LibXML         ();
use XML::Compile::Cache ();
use Scalar::Util        qw(blessed);
use List::Util          qw(first);
use XML::Compile::Util  qw(pack_type);

use Business::CAMT::Message ();

my $urnbase = 'urn:iso:std:iso:20022:tech:xsd';
my $moddir  = Path::Class::File->new(__FILE__)->dir;
my $xsddir  = $moddir->subdir('CAMT', 'xsd');
my $tagdir  = $moddir->subdir('CAMT', 'tags');
sub _rootElement($) { pack_type $_[1], 'Document' }  # $ns parameter

# The XSD filename is like camt.052.001.12.xsd.  camt.052.001.* is expected
# to be incompatible tiwh camt.052.002.*, but *.12.xsd can parse *.11.xsd
my (%xsd_files, $tagtable);

=encoding utf-8

=chapter NAME

Business::CAMT - ISO20022 Cash Management (CAMT) messages

=chapter SYNOPSIS

  my $camt = Business::CAMT->new;
  my $data = $camt->read($file|$xml);

=chapter DESCRIPTION

Use this module to manage CAMT messages, which are ISO20022 standard
"Cash Management" messages as produced in banking.  For instance,
CAMT.053 is produced by banks and consumed by accountancies, showing
transactions in bank-accounts.  See F<https://www.iso20022.org>.

At the moment, this module can be used to read and write the XML message
files.  It is intended to also support interpreting and construction
abstraction.  However, B<I need a sponsor> to make that happen.
Contact the author for support.  Please.

I would also like to include a CAMT.053 to MT-940 converter, v.v.
Please hire me.

=chapter METHODS

=section Constructors

=c_method new %options
Create a new CAMT processing object.

Reuse this object to avoid recompilation of the message reader.

=option  match_schema $rule
=default match_schema 'NEWER'
Sets the default $rule how to handle messages which have namespaces
which do not match the schemas contained in the module release.

See M<matchSchema()> for the available $rule values.  See the L<DETAILS>
section about the namespace versioning horrors.

=option  big_numbers BOOLEAN
=default big_numbers C<false>
Set to a true value when your accounts run into the billions.  This will
enable M<Math::BigFloat> to be used, which is slower and memory hungry.

=option  long_tagnames BOOLEAN
=default long_tagnames C<false>
The schemas are derived from an UML specifications which uses clear and
readible long names for relations and attributes.  But, someone with a
poor sense of optimization removed most of the vowels from these tags
while translating the UML into an XSD.  When set to C<true>, this option
will give you the nice long names in Perl.
=cut

sub new {
    my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($) {
	my ($self, $args) = @_;

	foreach my $f (grep !$_->is_dir && $_->basename =~ /\.xsd$/, $xsddir->children)
	{	$f->basename =~ /^camt\.([0-9]{3}\.[0-9]{3})\.([0-9]+)\.xsd$/ or panic $f;
		$xsd_files{$1}{$2} = $f->stringify;
	}

	$self->{BC_rule} = delete $args->{match_schema}  || 'NEWER';
	$self->{BC_big}  = delete $args->{big_numbers}   || 0;
	$self->{BC_long} = delete $args->{long_tagnames} || 0;
	$self->{RC_schemas} = XML::Compile::Cache->new;

    $self;
}

#-------------------------
=section Accessors

=method schemas
=cut

sub schemas() { $_[0]->{RC_schemas} }

#-------------------------
=section Read and Write messages

=method read $file|$xml, %options
Pass a $file name, an $xml document or an $xml node.  Returned is
a HASH blessed in class 'Business::CAMT::CAMT<nr>', for instance
C<Business::CAMT::CAMT053>.

=option  match_schema $rule
=default match_schema M<new(match_schema)>
=cut

sub read($%)
{	my ($self, $src, %args) = @_;

	my $dom = blessed $src ? $src : XML::LibXML->load_xml(location => $src);
	my $xml = $dom->isa('XML::LibXML::Document') ? $dom->documentElement : $dom;
	my $ns  = $xml->namespaceURI;
	my ($set, $version) = $ns =~ m!^\Q$urnbase\E:camt\.([0-9]{3}\.[0-9]{3})\.([0-9]+)$!
		or error __"Not a CAMT file.";

	my $versions = $xsd_files{$set}
		or error __"Not a supported CAMT message type.";

	my $xsd_version = $self->matchSchema($set, $version, rule => $args{match_schema})
		or error __"No compatible schema version available.";

	if($xsd_version != $version)
	{	# implement backwards compatibility
		trace "Using $set schema version $xsd_version to read a version $version message.";
		$ns = "$urnbase:camt.$set.$xsd_version";
		$xml->setNamespaceDeclURI('', $ns);
	}

	my $reader = $self->schemaReader($set, $xsd_version, $ns);

	Business::CAMT::Message->fromData(
		set     => $set,
		version => $xsd_version,
		data    => $reader->($xml),
		camt    => $self,
	);
}

=method create $set, $version, $data
=cut

sub create($$$)
{	my ($self, $set, $version, $data) = @_;
	Business::CAMT::Message->create(
		set     => $set,
		version => $version,
		data    => $data,
		camt    => $self,
	);
}

=method write $file, $message, %options

=example writing a message

  my $message = $camt->create('053.001', '02', $data);
  $camt->write('out.xml', $message);

=cut

sub write($$%)
{	my ($self, $fn, $msg, %args) = @_;

	my $set      = $msg->set;
	my $versions = $xsd_files{$set}
		or error __x"Message set '{set}' is unsupported.", set => $set;

	my @versions = sort { $a <=> $b } keys %$versions;
	my $version  = $msg->version;
	grep $version eq $_, @versions
		or error __x"Schema version {version} is not available, pick from {versions}.",
			version => $version, versions => \@versions;

	my $ns     = "$urnbase:camt.$set.$version";
	my $writer = $self->schemaWriter($set, $version, $ns);

	my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
	my $xml    = $writer->($doc, $msg);
	$doc->setDocumentElement($xml);
	$doc->toFile($fn, 1);
	$xml;
}

#-------------------------
=section Helper methods

You would rarely (or never) need to use these methods in your programs: they support
the reader and writer function.

=method schemaReader $set, $version, $ns
Produces a CODE which can be called with an XML message, to get it transformed
into a Perl data-structure.  In this case, the $set and $version have to be
known already; method M<read()> figures that out by itself.
=cut

sub _loadXsd($$)
{	my ($self, $set, $version) = @_;
	my $file = $xsd_files{$set}{$version};
	$self->{BC_loaded}{$file}++ or $self->schemas->importDefinitions($file);
}

my %msg_readers;
sub schemaReader($$$)
{	my ($self, $set, $version, $ns) = @_;
	my $r = $self->{BC_r} ||= {};
	return $r->{$ns} if $r->{$ns};

	$self->_loadXsd($set, $version);

	$r->{$ns} = $self->schemas->compile(
		READER        => $self->_rootElement($ns),
		sloppy_floats => !$self->{BC_big},
		key_rewrite   => $self->{BC_long} ? $self->tag2fullnameTable : undef,
	);
}

=method schemaWriter $set, $version, $ns
=cut

sub schemaWriter($$$)
{	my ($self, $set, $version, $ns) = @_;
	my $w = $self->{BC_w} ||= {};
	return $w->{$ns} if $w->{$ns};

	$self->_loadXsd($set, $version);
	$w->{$ns} = $self->schemas->compile(
		WRITER        => $self->_rootElement($ns),
		sloppy_floats => !$self->{BC_big},
		key_rewrite   => $self->{BC_long} ? $self->tag2fullnameTable : undef,
		ignore_unused_tags => qr/^_attrs$/,
		prefixes      => { $ns => '' },
	);
}


=method matchSchema $set, $version, %options
Find the available schema version for the $set (like '053.001') to interpret
a message with $version (like '02').

=option  rule 'EXACT'|'NEWER'|'NEWEST'|'ANY'|CODE
=default rule M<new(match_schema)>
When C<EXACT>, only the precise version is acceptable.  C<NEWER> will
fall back to the closest newer version.  When no exact match, C<NEWEST>
returns the highest available version, but must be newer.  Most generous
is C<ANY>, which falls back to the newest available version even when
it is older than the message version.

You may also pass a CODE reference, which is called with the $set, the requested
schema, and a sorted ARRAY of available versions.  It must return one of the
available versions or C<undef> (no compatible version).
=cut

# called with ($set, $version, \@available_versions)
sub _exact { first { $_[1] eq $_ } @{$_[2]} }
my %rules = (
	EXACT  => \&_exact,
	NEWER  => sub { (grep $_ >= $_[1], @{$_[2]})[0] },
	NEWEST => sub { _exact(@_) || ($_[1] <= $_[2][-1] ? $_[2][-1] : undef) },
	ANY    => sub { _exact(@_) || $_[2][-1] },
);

sub matchSchema($$%)
{	my ($self, $set, $version, %args) = @_;
	my $versions = $xsd_files{$set} or panic "Unknown set $set";

	my $ruler = $args{rule} ||= $self->{BC_rule};
	my $rule  = ref $ruler eq 'CODE' ? $ruler : $rules{$ruler}
		or error __x"Unknown schema match rule '{rule}'.", rule => $ruler;
	
	$rule->($set, $version, [ sort { $a <=> $b } keys %$versions ]);
}

=method knownVersions [$set]
Returns a sorted LIST with all schema versions which are included in this
distribution.  When the $set is specified (like C<053.001>), then only
those are reported.
=cut

sub knownVersions(;$)
{	my ($self, $set) = @_;
	my @s;
	foreach my $s ($set ? $set : sort keys %xsd_files)
	{	push @s, map "camt.$s.$_", sort {$a <=> $b} keys %{$xsd_files{$s}};
	}
	@s;
}

=method fullname2tagTable
Translates long and understandable names into (silly) abbreviated tags.
=cut

sub fullname2tagTable()
{	my $self = shift;
	$self->{BC_toAbbr} ||= +{ reverse %{$self->tag2fullnameTable} };
}

=method tag2fullnameTable
Returns a table which translates the (silly) abbreviations used in the
XML tags into readable names.  Good names make it easier to understand
the handling code and is less error-prone.
=cut

sub tag2fullnameTable()
{	my $self = shift;
	$self->{BC_toLong} ||= +{
		map split(/,/, $_, 2), grep !/,$/, $tagdir->file('index.csv')->slurp(chomp => 1)
	};
}

#---------------
=chapter DETAILS

In this chapter, you find some background information and implementation tips.

=section Examples

The release contains a C<examples/> directory.  In that directory, you with find
a C<show> script and some xml files.  Run the script with a file, to see what
this module has to offer.  For example:

  cd Business-CAMT-0.01/
  examples/show examples/danskeci.com/camt053_dk_example.xml /tmp/a.xml

The script (this module) auto-detects the CAMT type which is found in the XML
message.  Play with the script to see how changes affect the output.

=section Templates

In our GitHub repository, you find a C<templates/> directory which
contains a structural dump of each of the Perl data structure which is
produced (for M<read()>) or consumed (for C<write>, to be implemented)
by this module.

Be sure you understand anonymous HASHes and ARRAYs in Perl well, when you
start playing.  Do not forget that code gets more readible when you use
practical reference variables.

On GitHub, you will also find a C<templates-long/> directory full of
examples.  This demonstrates what option M<new(long_tagname)> does: it
will make the Perl datastructures readible.

=section Implementation issues

=subsection XML namespaces

The idea behind XML namespaces to include schema versioning is
fundamentally flawed.  The CAMT files form no exception in broken XML
concept.  Of course, schema versions are backwards compatible, so why
not design your versioning with that in mind?

This module bends the namespace use to hide these design mistakes into
flexible code.  Without full knowledge about existing and future versions
of the schemas, there is a powerfull configuration setting with M<matchSchema()>.
Please consider to contribute discovered issues to this module.

=subsection Tag abbreviations

XML is very verbose anyway, so it really does not help to abbreviate tags leaving
some vowels out.  This makes it harder to read messages and code.  It increases
the chance on stupid typos in the code.

=subsection No common types

Each schema is separate, although their type definitions are overlapping.  It is
not guaranteed that equal types will stay that way over time.  This may cause
instable code.  Probably, issues will not emerge because the schema files are
generated from a central UML model.

=subsection Missed chances on XML

The messages are designed with an UML tool, which means: limited to the features
of that tool and hindering the view on the quality of the schema.  This leads to
structures like:

  <Bal>
    <Tp>
      <CdOrPrtry>
         <Cd>OPBD</Cd>
      </CdOrPrtry>
    </Tp>
    <Amt Ccy="SEK">500000</Amt>
    <CdtDbtInd>CRDT</CdtDbtInd>
    <Dt>
      <Dt>2010-10-15</Dt>
    </Dt>
  </Bal>

In Perl, this leads to (C<long_tagnames> on)

  Balance => {
    Type => {
      CodeOrProperty => {
        Code => 'OPBD',
      }
    },
    Amount => {
      _ => '500000',
      Currency => 'SEK',
    },
    CreditDebitInd => 'CRDT',
    Date => {
      Date => '2010-10-15',
    },
  }

The XML schema, when B<designed> as XML schema, could have looked like

  <Credit Code="OPDB">
    <Amount Currency="SEK">500000</Amount>
    <Date>2010-10-15</Date>
  </Credit>

Also: use of substitutionGroups would have made messages so much
clearer and easier.
=cut

1;
