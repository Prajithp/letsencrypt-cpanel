package Cpanel::LetsEncrypt::cPanel;

use base 'Cpanel::LetsEncrypt';

use Encode;
use Cpanel::OpenSSL ();

sub new {
    my ( $class, %args ) = @_;

    my $self = {%args};

    bless $self, $class;

    if ( ref $self->{'api'} != 'Cpanel::LetsEncrypt::cPanel::LiveAPI' ) {
        die "Could not make connection to cPanel liveapi engine";
    }

    die "you must provide atleast one domain name" if !$self->{domain};
    die "The domain $self->{'domain'} not owned by you" if !$self->check_domain_ownership();

    $self->{'work_dir'}   = $self->{'api'}->get_home_dir() . '/.letsencrypt';
    $self->{'domain_dir'} = $self->{'work_dir'} . '/live';
    $self->{'accounts'}   = $self->{'work_dir'} . '/accounts';
    $self->{'openssl'}    = Cpanel::OpenSSL->new();

    return $self;
}

sub check_domain_ownership {
    my $self = shift;

    my $domains = $self->{'api'}->get_domains_list;

    return 1 if grep /^$self->{'domain'}$/, @{$domains};

    return 0;
}

sub _resolve_file_location {
    my $self = shift;

    for my $parrent_dir ( $self->{'work_dir'}, $self->{'domain_dir'}, $self->{'accounts'} ) {
        mkdir( $parrent_dir, 0700 ) or die "$! : $parrent_dir" unless -d $parrent_dir;
    }

    my $dir = $self->{'domain_dir'} . '/' . $self->{'domain'};
    if ( !-d $dir ) {
        mkdir( $dir, 0700 ) or die $!;
    }

    my $hash_ref = {
        'cert'     => join( '/', $dir, $self->{'domain'} . '.crt' ),
        'csr'      => join( '/', $dir, $self->{'domain'} . '.csr' ),
        'key'      => join( '/', $dir, $self->{'domain'} . '.key' ),
        'ca'       => join( '/', $dir, $self->{'domain'} . '.ca' ),
        'ca_der'   => join( '/', $dir, $self->{'domain'} . '_tmp_ca_.der' ),
        'cert_der' => join( '/', $dir, $self->{'domain'} . '_tmp_cert_.der' ),
    };

    return $hash_ref;
}

sub get_certificate {
    my $self = shift;

    my $file_location = $self->_resolve_file_location();
    my $userdata      = $self->{'api'}->get_domain_userdata( $self->{'domain'} );

    my $domains;
    if (defined $self->{aliases}) {
        $domains =  "$self->{domain}, $self->{aliases}";
    }
    else {
        $domains = $self->{domain};
    }

    my $hash = {
        'webroot-path' => $userdata->{'documentroot'},
        'domains'      => $domains,
        'domain'       => $self->{'domain'},
        'username'     => $userdata->{'user'},
    };

    my $status = $self->_request_for_ssl_cert($hash);

    if ( $status->{'success'} ) {
        my $result     = $self->{'api'}->install_ssl_certificate($hash);
        my $result_ref = $result->{'cpanelresult'}->{'result'};

        if ( !$result_ref->{'status'} ) {
            return {
                'message' => $result_ref->{'messages'}->[0],
                'success' => $result_ref->{'status'}
            };
        }
        return { 'message' => $result_ref->{'messages'}->[0], 'status' => $result_ref->{'status'} };
    }

    return $status;
}

1;
