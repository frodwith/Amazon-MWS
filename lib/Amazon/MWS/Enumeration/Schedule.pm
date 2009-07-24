package Amazon::MWS::Enumeration::Schedule;

use strict;
use warnings;

use base qw(Amazon::MWS::Enumeration);

__PACKAGE__->define qw(
    _15_MINUTES_
    _30_MINUTES_
    _1_HOUR_
    _2_HOURS_
    _4_HOURS_
    _8_HOURS_
    _12_HOURS_
    _1_DAY_
    _2_DAYS_
    _72_HOURS_
    _7_DAYS_
    _14_DAYS_
    _15_DAYS_
    _30_DAYS_
    _NEVER_
);

1;
