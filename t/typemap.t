use Test::More tests => 1;
use Amazon::MWS::TypeMap qw(:all);

my $example_date = '2009-02-20T02:10:35-08:00';
my $t = 'xs:datetime';
is(to_amazon($t, from_amazon($t, $example_date)), $example_date);
