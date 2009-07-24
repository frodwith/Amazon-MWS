package Amazon::MWS::Enumeration;

use strict;
use warnings;

use Exporter;

use overload '""' => \&as_string;

sub as_string { 
    my $self = shift; 
    return $$self;
}

sub define {
    my $class = shift;
    no strict 'refs';

    *{"${class}::import"} = *Exporter::import;

    foreach my $const (@_) {
        my $string = $const;
        my $ref    = \$string;
        bless $ref, $class;

        *{"${class}::$const"} = sub { $ref };
        push @{"${class}::EXPORT_OK"}, $const;
        push @{ ${"${class}::EXPORT_TAGS"}{'all'} }, $const;
    }
}

1;

__END__

=head1 NAME

Amazon::MWS::Enumeration

=head1 DESCRIPTION

Base class for enumeration values that stringify to themselves, used to
represent the various enum values defined in the MWS api.  Using these instead
of just raw strings buys you compile-time checking to make sure you didn't
misspell the rather long all-caps names.

=head1 SYNOPSIS

    package MyEnum;

    use base 'Amazon::MWS::Enumeration';

    __PACKAGE__->define qw(
       VALUE1
       VALUE2
    );

    # ... later ...
    use MyEnum qw(VALUE1);
    # or
    use MyEnum qw(:all);
    VALUE1 # returns an object that stringifies to "VALUE1"
    # or
    MyEnum->VALUE1
    # or
    MyEnum::VALUE1 # the same

=head1 METHODS

=head2 define ( @constants )

For each string passed, installs a class method / exportable sub into the
calling subclass by that name.  The value returned by that sub will be an
object blessed into the calling package which stringifies into the constant
itself, e.g. $class->CONSTANT eq 'CONSTANT';

=head2 as_string ()

The stringifier for these enums - simply dereferences the blessed scalar.

=cut
