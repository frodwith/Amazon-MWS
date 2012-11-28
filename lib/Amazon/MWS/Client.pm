package Amazon::MWS::Client;

use warnings;
use strict;

our $VERSION = '0.3';

use URI;
use Readonly;
use DateTime;
use XML::Simple;
use URI::Escape;
use MIME::Base64;
use Digest::SHA qw(hmac_sha256_base64);
use HTTP::Request;
use LWP::UserAgent;
use Class::InsideOut qw(:std);
use Digest::MD5 qw(md5_base64);
use Amazon::MWS::TypeMap qw(:all);

my $baseEx;
BEGIN { Readonly $baseEx => 'Amazon::MWS::Client::Exception' }

# Data for automatic throttling. First is the maximum request quota,
# second is the restore rate.

my %throttleconfig=(
    '*'                             => [ 10, 60 ],  # conservative default
    GetFeedSubmissionList           => [ 10, 45 ],
    GetFeedSubmissionResult         => [ 15, 60 ],
    GetReport                       => [ 15, 60 ],
    GetReportList                   => [ 10, 60 ],
    ManageReportSchedule            => [ 10, 45 ],
    UpdateReportAcknowledgements    => [ 10, 45 ],
    GetLowestOfferListingsForSKU    => [ 20,  2 ],  # restore rate is 10 items every second
);

use Exception::Class (
    $baseEx,
    "${baseEx}::MissingArgument" => {
        isa    => $baseEx,
        fields => 'name',
        alias  => 'arg_missing',
    },
    "${baseEx}::Transport" => {
        isa    => $baseEx,
        fields => [qw(request response)],
        alias  => 'transport_error',
    },
    "${baseEx}::Response" => {
        isa    => $baseEx,
        fields => [qw(errors xml)],
        alias  => 'error_response',
    },
    "${baseEx}::BadChecksum" => {
        isa    => $baseEx,
        fields => 'request',
        alias  => 'bad_checksum',
    },
);

readonly agent          => my %agent;
readonly endpoint       => my %endpoint;
readonly access_key_id  => my %access_key_id;
readonly secret_key     => my %secret_key;
readonly seller_id      => my %seller_id;
readonly marketplace_id => my %marketplace_id;
readonly throttling     => my %throttling;
readonly debugging      => my %debugging;

sub force_array {
    my ($hash, $key) = @_;
    my $val = $hash->{$key};

    if (!defined $val) {
        $val = [];
    }
    elsif (ref $val ne 'ARRAY') {
        $val = [ $val ];
    }

    $hash->{$key} = $val;
}

sub convert {
    my ($hash, $key, $type) = @_;
    $hash->{$key} = from_amazon($type, $hash->{$key});
}

sub convert_FeedSubmissionInfo {
    my $root = shift;
    force_array($root, 'FeedSubmissionInfo');

    foreach my $info (@{ $root->{FeedSubmissionInfo} }) {
        convert($info, SubmittedDate => 'datetime');
    }
}

sub convert_ReportRequestInfo {
    my $root = shift; 
    force_array($root, 'ReportRequestInfo');

    foreach my $info (@{ $root->{ReportRequestInfo} }) {
        convert($info, StartDate     => 'datetime');
        convert($info, EndDate       => 'datetime');
        convert($info, Scheduled     => 'boolean');
        convert($info, SubmittedDate => 'datetime');
    }
}

sub convert_ReportInfo {
    my $root = shift;
    force_array($root, 'ReportInfo');

    foreach my $info (@{ $root->{ReportInfo} }) {
        convert($info, AvailableDate => 'datetime');
        convert($info, Acknowledged  => 'boolean');
    }
}

sub convert_ReportSchedule {
    my $root = shift;
    force_array($root, 'ReportSchedule');

    foreach my $info (@{ $root->{ReportSchedule} }) {
        convert($info, ScheduledDate => 'datetime');
    }
}

sub slurp_kwargs { ref $_[0] eq 'HASH' ? shift : { @_ } }

sub define_api_method {
    my $method_name = shift;
    my $spec        = slurp_kwargs(@_);
    my $params      = $spec->{parameters};

    my $method = sub {
        my $self = shift;
        my $args = slurp_kwargs(@_);
        my $body;
        my %form = (
            Action           => $method_name,
            AWSAccessKeyId   => $self->access_key_id,
            SellerId         => $self->seller_id,
            MarketplaceId    => $self->marketplace_id,
            Version          => '2011-10-01',
            SignatureVersion => 2,
            SignatureMethod  => 'HmacSHA256',
            Timestamp        => to_amazon('datetime', DateTime->now),
        );

        $self->throttle($method_name);

        foreach my $name (keys %$params) {
            my $param = $params->{$name};

            unless (exists $args->{$name}) {
                arg_missing(name => $name) if $param->{required};
                next;
            }

            my $type  = $param->{type};
            my $value = $args->{$name};

            # Odd 'structured list' notation handled here
            if ($type =~ /(\w+)List/) {
                my $list_type = $1;
                my $counter   = 1;
                foreach my $sub_value (@$value) {
                    my $listKey = "$name.$list_type." . $counter++;
                    $form{$listKey} = $sub_value;
                }
                next;
            }

            if ($type eq 'HTTP-BODY') {
                $body = $value;
            }
            else {
                $form{$name} = to_amazon($type, $value);
            }
        }

        my $uri = URI->new($self->endpoint);
        $uri->path($spec->{path}.$form{Version}) if ($spec->{path});
        $uri->query_form(\%form);

        my $request = HTTP::Request->new;
        $request->uri($uri);

        if ($body) {
            $request->method('POST'); 
            $request->content($body);
            $request->header('Content-MD5' => md5_base64($body) . '==');
            $request->content_type($args->{content_type});
        }
        else {
            $request->method('GET');
        }

        $self->sign_request($request);

        if($debugging{id $self}) {
            print STDERR "REQUEST: ".$request->as_string."\n";
        }

        my $response = $self->agent->request($request);

        if($debugging{id $self}) {
            print STDERR "RESPONSE: ".$response->as_string."\n";
        }

        my $content  = $response->content;

        my $xs = XML::Simple->new( KeepRoot => 1 );

        if ($response->code == 400 || $response->code == 403) {
            my $hash = $xs->xml_in($content);
            my $root = $hash->{ErrorResponse};
            force_array($root, 'Error');
            error_response(errors => $root->{Error}, xml => $content);
        }

        unless ($response->is_success) {
            transport_error(request => $request, response => $response);
        }

        if (my $md5 = $response->header('Content-MD5')) {
            bad_checksum(response => $response) 
                unless ($md5 eq md5_base64($content) . '==');
        }

        return $content if $spec->{raw_body};

        my $hash = $xs->xml_in($content);

        my $root = $hash->{$method_name . 'Response'}
            ->{$method_name . 'Result'};

        return $spec->{respond}->($root);
    };

    my $fqn = join '::', __PACKAGE__, $method_name;
    no strict 'refs';
    *$fqn = $method;
}

sub sign_request {
    my ($self, $request) = @_;
    my $uri = $request->uri;
    my %params = $uri->query_form;
    my $canonical = join '&', map {
        my $param = uri_escape($_);
        my $value = uri_escape($params{$_});
        "$param=$value";
    } sort keys %params;

    ### print STDERR ">SIGNATURE: canonical=$canonical\n" if $debugging{id $self};

    my $string = $request->method . "\n"
        . $uri->authority . "\n"
        . $uri->path . "\n"
        . $canonical;

    ### print STDERR ">SIGNATURE: string=$string\n" if $debugging{id $self};

    my $sig=hmac_sha256_base64($string, $self->secret_key);
    $sig.='=' while length($sig) % 4;

    ### print STDERR ">SIGNATURE: signature=$sig\n" if $debugging{id $self};

    $params{Signature} = $sig;

    $uri->query_form(\%params);

    ### print STDERR ">SIGNATURE: uri=".$uri->as_string."\n" if $debugging{id $self};

    $request->uri($uri);
}

sub throttle {
    my ($self,$action)=@_;

    # TODO: Support bursts!

    my $cf=$throttleconfig{$action} || $throttleconfig{'*'} || return;

    my $td=$throttling{id $self}->{$action} || 0;

    my $now=time;

    my $wtime=$cf->[1] - ($now - $td);

    if($wtime>0) {
        print STDERR "..throttling $action for $wtime seconds\n" if $debugging{id $self};

        sleep $wtime;
    }

    $throttling{id $self}->{$action}=$now;
}

sub new {
    my $class = shift;
    my $opts  = slurp_kwargs(@_);
    my $self  = register $class;

    my $attr = $opts->{agent_attributes};
    $attr->{Language} = 'Perl';

    my $attr_str = join ';', map { "$_=$attr->{$_}" } keys %$attr;
    my $appname  = $opts->{Application} || 'Amazon::MWS::Client';
    my $version  = $opts->{Version}     || $VERSION;

    my $agent_string = "$appname/$version ($attr_str)";
    $agent{id $self} = LWP::UserAgent->new(agent => $agent_string);

    $endpoint{id $self} = $opts->{endpoint} || 'https://mws.amazonservices.com/';

    # Signature verification depends on the slash
    #
    $endpoint{id $self}.='/' unless $endpoint{id $self}=~/\/$/;

    $access_key_id{id $self} = $opts->{access_key_id}
        or die 'No access key id';

    $secret_key{id $self} = $opts->{secret_key}
        or die 'No secret key';

    $seller_id{id $self} = $opts->{seller_id}
        or die 'No seller id';

    $marketplace_id{id $self} = $opts->{marketplace_id}
        or die 'No marketplace id';

    $debugging{id $self} = $opts->{debug} || $opts->{'debugging'} || 0;

    $throttling{id $self} = { };

    return $self;
}

define_api_method SubmitFeed =>
    parameters => {
        FeedContent => {
            required => 1,
            type     => 'HTTP-BODY',
        },
        FeedType => {
            required => 1,
            type     => 'string',
        },
        PurgeAndReplace => {
            type     => 'boolean',
        },
    },
    respond => sub {
        my $root = shift->{FeedSubmissionInfo};
        convert($root, SubmittedDate => 'datetime');
        return $root;
    };

define_api_method GetFeedSubmissionList =>
    parameters => {
        FeedSubmissionIdList     => { type => 'IdList' },
        MaxCount                 => { type => 'nonNegativeInteger' },
        FeedTypeList             => { type => 'TypeList' },
        FeedProcessingStatusList => { type => 'StatusList' },
        SubmittedFromDate        => { type => 'datetime' },
        SubmittedToDate          => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_FeedSubmissionInfo($root);
        return $root;
    };

define_api_method GetFeedSubmissionListByNextToken =>
    parameters => { 
        NextToken => {
            type     => 'string',
            required => 1,
        },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_FeedSubmissionInfo($root);

        return $root;
    };

define_api_method GetFeedSubmissionCount =>
    parameters => {
        FeedTypeList             => { type => 'TypeList' },
        FeedProcessingStatusList => { type => 'StatusList' },
        SubmittedFromDate        => { type => 'datetime' },
        SubmittedToDate          => { type => 'datetime' },
    },
    respond => sub { $_[0]->{Count} };

define_api_method CancelFeedSubmissions =>
    parameters => {
        FeedSubmissionIdList => { type => 'IdList' },
        FeedTypeList         => { type => 'TypeList' },
        SubmittedFromDate    => { type => 'datetime' },
        SubmittedToDate      => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert_FeedSubmissionInfo($root);
        return $root;
    };

define_api_method GetFeedSubmissionResult =>
    raw_body   => 1,
    parameters => {
        FeedSubmissionId => { 
            type     => 'string',
            required => 1,
        },
    };

define_api_method RequestReport =>
    parameters => {
        ReportType => {
            type     => 'string',
            required => 1,
        },
        StartDate => { type => 'datetime' },
        EndDate   => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert_ReportRequestInfo($root);
        return $root;
    };

define_api_method GetReportRequestList =>
    parameters => {
        ReportRequestIdList        => { type => 'IdList' },
        ReportTypeList             => { type => 'TypeList' },
        ReportProcessingStatusList => { type => 'StatusList' },
        MaxCount                   => { type => 'nonNegativeInteger' },
        RequestedFromDate          => { type => 'datetime' },
        RequestedToDate            => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportRequestInfo($root);
        return $root;
    };

define_api_method GetReportRequestListByNextToken =>
    parameters => {
        NextToken => { 
            required => 1,
            type      => 'string',
        },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportRequestInfo($root);
        return $root;
    };

define_api_method GetReportRequestCount =>
    parameters => {
        ReportTypeList             => { type => 'TypeList' },
        ReportProcessingStatusList => { type => 'StatusList' },
        RequestedFromDate          => { type => 'datetime' },
        RequestedToDate            => { type => 'datetime' },
    },
    respond => sub { $_[0]->{Count} };

define_api_method CancelReportRequests =>
    parameters => {
        ReportRequestIdList        => { type => 'IdList' },
        ReportTypeList             => { type => 'TypeList' },
        ReportProcessingStatusList => { type => 'StatusList' },
        RequestedFromDate          => { type => 'datetime' },
        RequestedToDate            => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert_ReportRequestInfo($root);
        return $root;
    };

define_api_method GetReportList =>
    parameters => {
        MaxCount            => { type => 'nonNegativeInteger' },
        ReportTypeList      => { type => 'TypeList' },
        Acknowledged        => { type => 'boolean' },
        AvailableFromDate   => { type => 'datetime' },
        AvailableToDate     => { type => 'datetime' },
        ReportRequestIdList => { type => 'IdList' },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportInfo($root);
        return $root;
    };

define_api_method GetReportListByNextToken =>
    parameters => {
        NextToken => {
            type     => 'string',
            required => 1,
        },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportInfo($root);
        return $root;
    };

define_api_method GetReportCount =>
    parameters => {
        ReportTypeList      => { type => 'TypeList' },
        Acknowledged        => { type => 'boolean' },
        AvailableFromDate   => { type => 'datetime' },
        AvailableToDate     => { type => 'datetime' },
    },
    respond => sub { $_[0]->{Count} };

define_api_method GetReport =>
    raw_body   => 1,
    parameters => {
        ReportId => { 
            type     => 'string',
            required => 1,
        }
    };

define_api_method ManageReportSchedule =>
    parameters => {
        ReportType    => { type => 'string' },
        Schedule      => { type => 'string' },
        ScheduledDate => { type => 'datetime' },
    },
    respond => sub {
        my $root = shift;
        convert_ReportSchedule($root);
        return $root;
    };

define_api_method GetReportScheduleList =>
    parameters => {
        ReportTypeList => { type => 'ReportType' },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportSchedule($root);
        return $root;
    };

define_api_method GetReportScheduleListByNextToken =>
    parameters => {
        NextToken => {
            type     => 'string',
            required => 1,
        },
    },
    respond => sub {
        my $root = shift;
        convert($root, HasNext => 'boolean');
        convert_ReportSchedule($root);
        return $root;
    };

define_api_method GetReportScheduleCount =>
    parameters => {
        ReportTypeList => { type => 'ReportType' },
    },
    respond => sub { $_[0]->{Count} };

define_api_method UpdateReportAcknowledgements =>
    parameters => {
        ReportIdList => { 
            type     => 'IdList',
            required => 1,
        },
        Acknowledged => { type => 'boolean' },
    },
    respond => sub {
        my $root = shift;
        convert_ReportInfo($root);
        return $root;
    };

define_api_method GetMatchingProductForId =>
    path => '/Products/',
    parameters => {
        IdList => {
            type     => 'IdList',
            required => 1,
        },
        IdType => { type => 'string' },
    },
    respond => sub {
        my $root = shift;
        if (ref($root) ne 'ARRAY') {
          $root = [ $root ];
        }
        return $root;
    };

define_api_method GetLowestOfferListingsForSKU =>
    path => '/Products/',
    parameters => {
        SellerSKUList => {
            type     => 'SellerSKUList',
            required => 1,
        },
        ItemCondition => { type => 'string' },
        ExcludeMe => { type => 'boolean' },
    },
    respond => sub {
        my $root = shift;
        if (ref($root) ne 'ARRAY') {
          $root = [ $root ];
        }
        foreach my $product (@$root) {
          force_array($product->{Product}->{LowestOfferListings}, 'LowestOfferListing');
        }
        return $root;
    };

1;

__END__

=head1 NAME

Amazon::MWS::Client

=head1 DESCRIPTION

An API binding for Amazon's Marketplace Web Services.  An overview of the
entire interface can be found at L<https://mws.amazon.com/docs/devGuide>.

=head1 METHODS

=head2 new

Constructs a new client object.  Takes the following keyword arguments:

=head3 agent_attributes

An attributes you would like to add (besides language=Perl) to the user agent
string, as a hashref.

=head3 application

The name of your application.  Defaults to 'Amazon::MWS::Client'

=head3 version

The version of your application.  Defaults to the current version of this
module.

=head3 endpoint

Where MWS lives.  Defaults to 'https://mws.amazonservices.com/'.

=head3 access_key_id

Your AWS Access Key Id

=head3 secret_key

Your AWS Secret Access Key

=head3 seller_id

Your Amazon Seller (Merchant) ID

=head3 marketplace_id

The marketplace id for the calls being made by this object.

=head1 EXCEPTIONS

Any of the L<API METHODS> can throw the following exceptions
(Exception::Class).  They are all subclasses of Amazon::MWS::Exception.

=head2 Amazon::MWS::Exception::MissingArgument

The call to the API method was missing a required argument.  The name of the
missing argument can be found in $e->name.

=head2 Amazon::MWS::Exception::Transport

There was an error communicating with the Amazon endpoint.  The HTTP::Request
and Response objects can be found in $e->request and $e->response.

=head2 Amazon::MWS::Exception::Response

Amazon returned an response, but indicated an error.  An arrayref of hashrefs
corresponding to the error xml (via XML::Simple on the Error elements) is
available at $e->errors, and the entire xml response is available at $e->xml.

=head2 Amazon::MWS::Exception::BadChecksum

If Amazon sends the 'Content-MD5' header and it does not match the content,
this exception will be thrown.  The response can be found in $e->response.

=head1 API METHODS

The following methods may be called on objects of this class.  All concerns
(such as authentication) which are common to every request are handled by this
class.  

Enumerated values may be specified as strings or as constants from the
Amazon::MWS::Enumeration packages for compile time checking.  

All parameters to individual API methods may be specified either as name-value
pairs in the argument string or as hashrefs, and should have the same names as
specified in the API documentation.  

Return values will be hashrefs with keys as specified in the 'Response
Elements' section of the API documentation unless otherwise noted.

The mapping of API datatypes to perl datatypes is specified in
L<Amazon::MWS::TypeMap>.  Note that where the documentation calls for a
'structured list', you should pass in an arrayref.

=head2 SubmitFeed

Requires an additional 'content_type' argument specifying what content type
the HTTP-BODY is.

=head2 GetFeedSubmissionList

=head2 GetFeedSubmissionListByNextToken

=head2 GetFeedSubmissionCount

Returns the count as a simple scalar (as do all methods ending with Count)

=head2 CancelFeedSubmissions

=head2 GetFeedSubmissionResult

The raw body of the response is returned.

=head2 RequestReport

The returned ReportRequest will be an arrayref for consistency with other
methods, even though there will only ever be one element.

=head2 GetReportRequestList

=head2 GetReportRequestListByNextToken

=head2 GetReportRequestCount

=head2 CancelReportRequests

=head2 GetReportList

=head2 GetReportListByNextToken

=head2 GetReportCount

=head2 GetReport

The raw body is returned.

=head2 ManageReportSchedule

=head2 GetReportScheduleList

=head2 GetReportScheduleListByNextToken

=head2 GetReportScheduleCount

=head2 UpdateReportAcknowledgements

=head2 GetLowestOfferListingsForSKU

=head1 AUTHOR

Paul Driver C<< frodwith@cpan.org >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009, Plain Black Corporation L<http://plainblack.com>.
All rights reserved

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.
