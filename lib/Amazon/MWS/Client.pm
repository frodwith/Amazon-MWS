package Amazon::MWS::Client;

use warnings;
use strict;

our $VERSION = '0.1';

use URI;
use XML::Simple;
use HTTP::Request;
use Class::InsideOut qw(:std);
use Digest::MD5 qw(md5_base64);
use Amazon::MWS::TypeMap qw(:all);

private agent => my %agent;

sub slurp_kwargs { ref $_[0] eq 'HASH' ? shift : { @_ } }

sub define_api_method {
    my $spec        = slurp_kwargs(@_);
    my $method_name = $spec->{name};
    my $params      = $spec->{parameters};

    my $method = sub {
        my $self = shift;
        my $args = slurp_kwargs(@_);
        my $body;
        my %form = (Action => $method_name);

        foreach my $name (keys %$params) {
            $param = $params->{$name};

            unless (exists $args->{$name}) {
                arg_missing(name => $name) if $param->{required};

                if (my $default = $param->{default}) {
                    $form{$name} = $default;
                }

                next;
            }

            my $type  = $param->{type};
            my $value = to_amazon($type, $args->{$name});

            if ($type eq 'HTTP-BODY') {
                $body = $value;
            }
            else {
                $form{$name} = $value; 
            }
        }

        my $uri = URI->new($self->endpoint);
        $uri->query_form(\%form);

        my $request = HTTP::Request->new;
        $request->uri($uri);

        if ($body) {
            $request->method('POST'); 
            $request->content($body);
            $request->header('Content-MD5' => md5_base64($body));
            $request->content_type(
        }
        else {
            $request->method('GET');
        }

        $self->set_auth_headers($request);
        my $response = $self->agent->request($request);

        unless ($response->is_success) {
            transport_error(request => $request);
        }

        my $xs = XML::Simple->new(
            KeepRoot => 1,
        );
        $response = $xs->xml_in($response);

        if ($response->{ErrorResponse}) {
            my $errors = $response->{Error};        
            $errors = [ $errors ] unless (ref $errors eq 'ARRAY');
            error_response(errors => $errors);
        }

        return $spec->{respond}->($response);
    };

    my $fqn = join '::', __PACKAGE__, $method_name;
    no strict 'refs';
    *$fqn = $method;
}

sub new {
    my $class = shift;
    my $opt   = slurp_kwargs(@_);
    my $self  = register $class;

    my $attr = $opt->{agent_attributes};
    $attr->{language} = 'Perl';

    my $attr_str = join ';', map { "$_=$attr->{$_}" } keys %$attr;
    my $appname  = $opts->{application} || 'Amazon::MWS::Client';
    my $version  = $opts->{version}     || $VERSION;

    $agent{id $self} = LWP::UserAgent->new("$appname/$version ($attr_str)");

    return $self;
}

define_api_method(
    name       => 'SubmitFeed',
    parameters => {
        FeedContent => {
            required => 1,
            type     => 'HTTP-BODY'
        },
        FeedType => {
            required => 1,
            type     => 'xs:string',
        },
        PurgeAndReplace => {
            type     => 'xs:boolean',
            default  => 'false',
        },
    },
    respond => sub {
        my $root = $_[0]->{SubmitFeedResponse}->{SubmitFeedResult};
        $root->{SubmittedDate} = 
            from_amazon('xs:datetime', $root->{SubmittedDate});
        return $root;
    },
);

1;

__END__

=head1 NAME

Amazon::MWS::Client

=head1 DESCRIPTION

An API binding for Amazon's Merchant Web Services.  An overview of the entire interface can be found at L<https://mws.amazon.com/docs/devGuide>.

=head1 METHODS

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
Elements' section of the API documentation.

The mapping of API datatypes to perl datatypes is specified in
L<Amazon::MWS::TypeMap>.

=head2 SubmitFeed

=head2
