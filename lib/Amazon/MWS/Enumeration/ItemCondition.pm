package Amazon::MWS::Enumeration::ItemCondition;

use strict;
use warnings;

use base qw(Amazon::MWS::Enumeration);

__PACKAGE__->define qw(
    Any
    New
    Used
    Collectible
    Refurbished
    Club
);

1;

__END__

=head1 NAME

Amazon::MWS::Enumeration::ItemCondition

=head1 CONSTANTS

=over 4

=item Any

=item New

=item Used

=item Collectible

=item Refurbished

=item Club

=back

=head1 SEE ALSO

L<Amazon::MWS::Enumeration>

=head1 AUTHOR

Blayne Puklich C<< blayne@excelcycle.com >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2012, excelcycle L<http://www.excelcycle.com>.
All rights reserved

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.
