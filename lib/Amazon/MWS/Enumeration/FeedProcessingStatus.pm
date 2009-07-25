package Amazon::MWS::Enumeration::FeedProcessingStatus;

use strict;
use warnings;

use base qw(Amazon::MWS::Enumeration);

__PACKAGE__->define qw(
    _SUBMITTED_
    _IN_PROGRESS_
    _CANCELLED_
    _DONE_
);

1;
