package Cpanel::LetsEncrypt::Service;

use base Cpanel::LetsEncrypt;

use Cpanel::LetsEncrypt::WHM ();
use Cpanel::OpenSSL          ();
use Cpanel::SSL::Utils       ();

sub new {
    my $class = shift;

    my $self = {};

    bless $self, $class;

    $self->{'whmapi'}       = Cpanel::LetsEncrypt::WHM->new();
    $self->{'work_dir'}     = '/var/letsencrypt';
    $self->{'hostname_dir'} = $self->{'work_dir'} . '/live';
    $self->{'accounts'}     = $self->{'work_dir'} . '/accounts';
    $self->{'openssl'}      = Cpanel::OpenSSL->new();
    $self->{'domain'}       = $self->_get_hostname();

    return $self;
}

sub _get_hostname {
    my $self = shift;

    my $api_ref  = $self->{'whmapi'}->liveapi_request('gethostname');
    my $hostname = $api_ref->{'data'}->{'hostname'};

    return $hostname;
}

sub _resolve_file_location {
    my $self = shift;

    my $hostname = $self->_get_hostname();

    for my $parrent_dir ( $self->{'work_dir'}, $self->{'hostname_dir'}, $self->{'accounts'} ) {
        mkdir( $parrent_dir, 0700 ) or die $! unless -d $parrent_dir;
    }

    my $dir = $self->{hostname_dir} . '/' . $self->{'domain'};
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

    my $hash = {
        'rsa-key-size'     => '4096',
        'authenticator'    => 'webroot',
        'webroot-path'     => '/usr/local/apache/htdocs/',
        'server'           => 'https://acme-v01.api.letsencrypt.org/directory',
        'renew-by-default' => 'True',
        'agree-tos'        => 'True',
        'email'            => $self->{'domain'},
        'domains'          => $self->{'domain'},
        'domain'           => $self->{'domain'},
        'username'         => 'root',
    };

    my $status = $self->_request_for_ssl_cert($hash);

    return $status;
}

sub install_cert_for_service {
    my ( $self, $services ) = @_;

    my ( $ok, $message );
    foreach my $service ( @{$services} ) {
        ( $ok, $message ) = $self->_install_cert($service);
        if ( !$ok ) {
            last;
        }
    }

    return wantarray ? ( $ok, $message ) : $ok;
}

sub _install_cert {
    my ( $self, $service ) = @_;

    my $cert_file = "/var/letsencrypt/live/" . $self->{'domain'} . '/' . $self->{domain} . '.crt';
    my $key_file  = "/var/letsencrypt/live/" . $self->{'domain'} . '/' . $self->{domain} . '.key';
    my $ca_file   = "/var/letsencrypt/live/" . $self->{'domain'} . '/' . $self->{domain} . '.ca';

    my $cert     = $self->slurp($cert_file);
    my $key      = $self->slurp($key_file);
    my $cabundle = $self->slurp($ca_file);

    my $status = $self->{'whmapi'}->liveapi_request(
        'install_service_ssl_certificate',
        {   'api.version' => '1',
            'service'     => $service,
            'crt'         => $cert,
            'key'         => $key,
            'cabundle'    => $cabundle,
        }
    );

    if ( !$status->{'metadata'}->{'result'} ) {
        return wantarray ? ( '0', $status->{'metadata'}->{'reason'} ) : '0';
    }

    return wantarray ? ( '1', $status->{'metadata'}->{'reason'} ) : '1';
}

sub check_for_expiry {
    my $self = shift;

    my $cert_file = "/var/letsencrypt/live/" . $self->{'domain'} . '/' . $self->{domain} . '.crt';
    if ( -e $cert_file ) {
        my $crt      = $self->slurp($cert_file);
        my $crt_info = Cpanel::SSL::Utils::parse_certificate_text($crt);

        my $days_left = int( ( $crt_info->{'not_after'} - time() ) / 86400 );

        if ( $days_left < '30' and $crt_info->{'issuer'}->{organizationName} =~ m{Let\'s\s+Encrypt}i) {
            my $result_ref = $self->get_certificate();
            if ( $result_ref->{'success'} ) {
                my @services = ( 'cpanel', 'exim', 'ftp', 'dovecot' );
                my ( $ok, $message ) = $self->install_cert_for_service( \@services );
                die $message if !$ok;
            }
            else {
                die $result_ref->{'message'};
            }
        }
        return $ok;
    }
    return;
}

1;
