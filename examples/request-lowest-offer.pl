
use strict;

use Amazon::MWS::Enumeration::ItemCondition qw(:all);
use Amazon::MWS::Client;
use DateTime;
use Data::Dumper;

my $mws = Amazon::MWS::Client->new(access_key_id=>"XXX",
                                   secret_key => "YYY",
                                   seller_id => "ZZZ",
                                   marketplace_id => "VVV");

my @skus = qw(1234 2345 3456 4567 5678);

my $req;

eval {
    $req = $mws->GetLowestOfferListingsForSKU(SellerSKUList => \@skus, ItemCondition => New, ExcludeMe => 1);
};

if(my $e = Exception::Class->caught('Amazon::MWS::Client::Exception')) {
    die $e->error . "\n" . $e->trace->as_string . "\n";
}
elsif($@) {
    die $@;
}

sub process_product {
  my $product = shift;
  my $lowest;
  foreach my $offer (@{$product->{Product}->{LowestOfferListings}->{LowestOfferListing}}) {
    if (!defined($lowest) || $offer->{Price}->{LandedPrice}->{Amount} > 0 && $offer->{Price}->{LandedPrice}->{Amount} < $lowest) {
      $lowest = $offer->{Price}->{LandedPrice}->{Amount} ;
    }
  }
  print $product->{SellerSKU}." lowest price ".$lowest."\n";
}

if (ref($req) eq 'ARRAY') {
  foreach my $product (@$req) {
    process_product($product);
  }
} else {
  process_product($req);
}
