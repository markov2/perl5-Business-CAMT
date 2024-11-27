# This code is part of distribution Business::CAMT.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

package Business::CAMT::Message;

use strict;
use warnings;

use Log::Report 'business-camt';
use Scalar::Util  qw/weaken/;

=encoding utf-8

=chapter NAME

Business::CAMT::Message - base class for messages

=chapter SYNOPSIS

  my $camt = Business::CAMT->new(...);

  my $msg  = $camt->read(...);
  my $msg  = $camt->create(...);

  $msg->write('file.xml');
  print $msg->toPerl;

=chapter DESCRIPTION

This module is the base class for objects which are able to interpret
the CAMT messages.

=chapter METHODS

=section Constructors

=c_method new %options
The data (probably read from a file) is wrapped into this class.  When
C<data> is undef, then C<undef> will be returned.

=requires set STRING
=requires version STRING
=requires data HASH
=requires camt M<Business::CAMT> object
=cut

sub new
{	my ($class, %args) = @_;
	my $data = delete $args{data} or return undef;
    (bless $data, $class)->init(\%args);
}

sub init($) {
	my ($self, $args) = @_;

	my %attrs;
	$attrs{set}     = $args->{set}     or panic;
	$attrs{version} = $args->{version} or panic;
	$attrs{camt}    = $args->{camt}    or panic;
	weaken $attrs{camt};
	$self->{_attrs} = \%attrs;

	$self;
}

=c_method fromData %options
This method accepts the same %options as N<new()>.  All options
passed in are passed to that constructor.
=cut

sub _loadSubclass($)
{	my ($class, $set) = @_;
	$class eq __PACKAGE__ or return $class;
	my $super = 'Business::CAMT::CAMT'.($set =~ s/\..*//r);

	# Is there a special implementation for this type?  Otherwise create
	# an empty placeholder.
	no strict 'refs';
	eval "require $super" or @{"$super\::ISA"} = __PACKAGE__;
	$super;
}

sub fromData(%)
{	my ($class, %args) = @_;
	my $set = $args{set} or panic;
	$class->_loadSubclass($set)->new(%args);
}

#-------------------------
=section Accessors

=method set
=method version
=method camt
=cut

sub set     { $_[0]->{_attrs}{set} }
sub version { $_[0]->{_attrs}{version} }
sub camt    { $_[0]->{_attrs}{camt} }

#-------------------------
=section Other

=method write $file, %options
All %options are passed to M<Business::CAMT::write()>.

=examples for write
   $msg->write($file);
   $camt->write($file, $msg);   # same
=cut

sub write(%)
{	my ($self, $file) = (shift, shift);
	$self->camt->write($file, $self, @_);
}

=method toPerl
Convert the HASH into Perl code, using M<Data::Dumper>.  This is
useful, because you do not want to include the hidden object
attributes in your output.
=cut

sub toPerl()
{	my $self = shift;
	my $attrs = delete $self->{_attrs};

	my $d = Data::Dumper->new([$self], 'MESSAGE');
	$d->Sortkeys(1)->Quotekeys(0)->Indent(1);
	my $text = $d->Dump;

	$self->{_attrs} = $attrs;
	$text;
}

1;
