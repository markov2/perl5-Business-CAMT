# This code is part of distribution Business::CAMT.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

package Business::CAMT::Message;

use strict;
use warnings;

use Log::Report 'business-camt';

=encoding utf-8

=chapter NAME

Business::CAMT::Message - base class for messages

=chapter SYNOPSIS

  # instantiated via the super classes

=chapter DESCRIPTION

This module is the base class for objects which are able to interpret
the CAMT messages.

=chapter METHODS

=section Constructors

=c_method new %options
=cut

sub new {
    my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($) {
	my ($self, $args) = @_;
	$self;
}

=c_method fromData $set, $data, %options
The $data (probably read from a file) is wrapped into this class.
=cut

sub fromData($$%)
{	my ($class, $set, $data, %args) = @_;
	my $super = $class eq __PACKAGE__ ? 'Business::CAMT::CAMT'.($set =~ s/\..*//r) : $class;

	# Is there a special implementation for this type?  Otherwise create
	# an empty placeholder.
	no strict 'refs';
	eval "require $super" or @{"$super\::ISA"} = __PACKAGE__;

	bless $data, $super;
}

#-------------------------
=section Accessors
=cut

1;
