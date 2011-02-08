use Module::Build;

my $build = Module::Build->new(
    dist_name         => 'Amazon-MWS',
    dist_version_from => 'lib/Amazon/MWS/Client.pm',
    dist_author       => 'Paul Driver <paul@plainblack.com>',
    license           => 'perl',
    dist_abstract     => 'Perl interface to Amazon Marketplace Web Services',

    build_requires => {
        'Test::More'                => 0,
        'Test::MockObject'          => 0,
        'Test::MockObject::Extends' => 0,
        'HTTP::Response'            => 0,
    },

    requires => {
        'URI'            => 0, 
        'URI::Escape'    => 0,
        'HTTP::Request'  => 0,
        'LWP::UserAgent' => 0,
        'XML::Simple'    => 0,

        'DateTime'                  => 0,
        'DateTime::Format::ISO8601' => 0,

        'Readonly'         => 0,
        'Class::InsideOut' => 0,
        'Exception::Class' => 0,
        'Exporter'         => 0,

        'MIME::Base64'      => 0,
        'Digest::MD5'       => 0,
        'Digest::HMAC_SHA1' => 0,
    },
);

$build->create_build_script();

