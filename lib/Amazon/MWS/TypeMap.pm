package Amazon::MWS::TypeMap;

use warnings;
use strict;

use DateTime;

use Exporter qw(import);
our @EXPORT_OK = qw(from_amazon to_amazon);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub identity { shift }

my %from_map = (
    'xs:string'   => \&identity,
    'xs:boolean'  => sub { shift eq 'true' },
    'xs:datetime' => sub {
        my $str    = shift;
        my $parser = qr/^
            (\d{4})- # year
            (\d\d)-  # month
            (\d\d)   # day
            T
            (\d\d):  # hour
            (\d\d):  # minute
            (\d\d)   # second
            ([+-])   # sign on timezone offset
            (\d\d):  # offset in hours
            (\d\d)   # offset in minutes
        $/x;
        my ($yr, $mo, $day, $h, $m, $s, $tzs, $tzh, $tzm) = $str =~ $parser;
        my $offset = $tzs . $tzh . $tzm;
        return DateTime->new(
            year      => $yr,
            month     => $mo,
            day       => $day,
            hour      => $h,
            minute    => $m,
            second    => $s,
            time_zone => $offset,
        );
    }
);

sub from_amazon {
    my ($type, $value) = @_;
    return $from_map{$type}->($value);
}

my %to_map = (
    'xs:string'   => \&identity,
    'xs:boolean'  => sub { $_[0] ? 'true' : 'false' },
    'xs:datetime' => sub { 
        my $dt     = shift;
        my $tz     = $dt->time_zone;
        my $offset = $tz->offset_for_datetime($dt);
        my $neg    = $offset < 0;

        $offset = -$offset if $neg;

        my $minutes = $offset  / 60;
        my $hours   = $minutes / 60;
        $minutes   -= $hours   * 60;

        my $offstr = sprintf '%s%02d:%02d', $neg ? '-' : '+', $hours, $minutes;
        return $dt->strftime("%FT%T$offstr");
    },
);

sub to_amazon {
    my ($type, $value) = @_;
    return $to_map{$type}->($value);
}

1;

__END__

=head1 NAME

Amazon::MWS::TypeMap

=head1 DESCRIPTION

Functions for mapping between types specified in the MWS API documentation and
perl datatypes.

=head1 EXPORTED FUNCTIONS

=head2 to_amazon ( type, value )

Converts from a perl datatype to a string for use as an MWS param.

=head2 from_amazon ( type, value )

Converts from a string supplied by MWS to a perl datatype.

=head1 TYPES

=head2 HTTP-BODY

Should be either a reference to a scalar containing the data to send,
a string containing the filename of the file to read from, or a filehandle.

=head2 xs:string

A plain perl string.

=head2 xs:boolean

When sent by amazon, true is converted to 1 and false to the empty string.
When sent to amazon, any true value or false value will be properly converted.

=head2 xs:datetime

Converted to and from DateTime objects.
