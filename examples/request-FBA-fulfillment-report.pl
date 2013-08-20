# Initiate FBA fulfillment report generation

use strict;

use Amazon::MWS::Enumeration::ReportType qw(:all);
use Amazon::MWS::Client;
use DateTime;

my $mws = Amazon::MWS::Client->new(access_key_id=>"XXX",
                                   secret_key => "YYY",
                                   merchant_id => "ZZZ",
                                   marketplace_id => "VVV");

my $req;

eval {
    $req = $mws->RequestReport(ReportType => (_GET_AMAZON_FULFILLED_SHIPMENTS_DATA_),
                              StartDate => DateTime->now->add(weeks => -1),
                              EndDate => DateTime->now);
};

if(my $e = Exception::Class->caught('Amazon::MWS::Client::Exception')) {
    die $e->error . "\n" . $e->trace->as_string . "\n";
}
elsif($@) {
    die $@;
}

if (my $req_id = $req->{ReportRequestInfo}->[0]->{ReportRequestId}) {
    open my $req, "> request.${req_id}";
    close $req;
}
