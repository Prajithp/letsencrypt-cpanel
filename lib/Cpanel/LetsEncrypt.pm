package Cpanel::LetsEncrypt;

use strict;
use JSON                           ();
use IPC::Open3                     ();
use File::Temp                     ();
use Data::Dumper                   ();
use Cpanel::YAML                   ();
use Cpanel::LetsEncrypt::Challenge ();
use Protocol::ACME                 ();
use Cpanel::OpenSSL                ();
use Cpanel::LetsEncrypt::WHM       ();
use Cpanel::LetsEncrypt::Config    ();

our $VERSION = '1.4';

sub new {
    my ( $class, %opts ) = @_;

    my $self = {%opts};

    die "you must provide atleast one domain name" if ( !$self->{domain} );

    bless( $self, $class );

    $self->_init;

    return $self;
}

sub _init {
    my $self = shift;

    $self->{openssl} = Cpanel::OpenSSL->new();
    $self->{whm}     = Cpanel::LetsEncrypt::WHM->new();

    my $domainuserdata = $self->{whm}->get_domain_userdata( $self->{domain} );

    die "Could not find username of this domain '$self->{domain}'" unless $domainuserdata->{user};

    $self->{work_dir}   = '/var/letsencrypt';
    $self->{domain_dir} = $self->{work_dir} . '/live';
    $self->{accounts}   = $self->{work_dir} . '/accounts';

    for my $dir ( $self->{work_dir}, $self->{domain_dir}, $self->{accounts} ) {
        mkdir $dir unless -d $dir;
    }

}

sub activate_ssl_certificate {
    my $self = shift;

    my $return_vars = _get_default_output_hash();

    if ( !$self->{'domain'} ) {
        $return_vars->{'message'} = "You must provide atleast one domain name";
        return $return_vars;
    }

    if ( $self->has_active_ssl_cert ) {
        $return_vars->{'message'} =
            "The domain $self->{domain} already has an active SSL certificate";
        return $return_vars;
    }

    my $json_resp = $self->{whm}->get_domain_userdata( $self->{domain} );

    my $domains;
    if (defined $self->{aliases}) { 
        $domains =  "$self->{domain}, $self->{aliases}";
    }
    else {
        $domains = $self->{domain};
    }

    my $hash = {
        'webroot-path' => $json_resp->{documentroot},
        'ip_address'   => $json_resp->{ip},
        'domains'      => $domains,
        'domain'       => $self->{domain},
        'username'     => $json_resp->{user},
    };

    my $status = $self->_request_for_ssl_cert($hash);

    if ( !$status->{'success'} ) {
        $return_vars->{'message'} = $status->{'message'};
        return $return_vars;
    }

    my ( $ok, $message ) = $self->{whm}->install_ssl_certificate($hash);

    if ( !$ok ) {
        $return_vars->{'message'} =
              $message
            ? $message
            : "cPanel SSL certificate installation failed, please check the log file for more info";
        return $return_vars;
    }

    $return_vars->{'status'}  = '1';
    $return_vars->{'message'} = 'Successfully installed SSL certificate';

    return $return_vars;
}

sub renew_ssl_certificate {
    my $self = shift;

    my $return_vars = _get_default_output_hash();

    if ( !$self->{'domain'} ) {
        $return_vars->{'message'} = "You must provide atleast one domain name";
        return $return_vars;
    }

    my $json_resp = $self->{whm}->get_domain_userdata( $self->{domain} );
    my $ssl_enabled_aliases = $self->{whm}->get_ssl_vhost_by_domain($self->{domain})->{'domains'};

    my $domains;
    if (scalar $ssl_enabled_aliases) {
        $domains  = join(',', @$ssl_enabled_aliases);
    }
    else {
        $domains = $self->{domain};
    }

    my $hash = {
        'webroot-path' => $json_resp->{documentroot},
        'ip_address'   => $json_resp->{ip},
        'domains'      => $domains,
        'domain'       => $self->{domain},
        'username'     => $json_resp->{user},
    };
    my $status = $self->_request_for_ssl_cert($hash);

    if ( !$status->{'success'} ) {
        $return_vars->{'message'} = $status->{'message'};
        return $return_vars;
    }

    my ( $ok, $message ) = $self->{whm}->install_ssl_certificate($hash);

    if ( !$ok ) {
        $return_vars->{'message'} =
              $message
            ? $message
            : "cPanel SSL installation failed, please check the log file for more info";
        return $return_vars;
    }

    $return_vars->{'status'} = '1';
    $return_vars->{'message'} = $message ? $message : 'Successfully installed SSL certificate';

    return $return_vars;
}

sub _request_for_ssl_cert {
    my ( $self, $hash ) = @_;

    my $result_hash = { 'message' => '', 'success' => '0', };

    my $account_key = $self->create_account_key( $hash->{email} );
    my $csr_file    = $self->_create_csr($hash);

    my $ca_file   = $self->_resolve_file_location()->{'ca'};
    my $cert_file = $self->_resolve_file_location()->{'cert'};

    if ( !-e $csr_file ) {
        $result_hash->{success} = '0';
        $result_hash->{message} =
            $csr_file->{message} ? $csr_file->{message} : "Could not create csr file";

        return $result_hash;
    }

    my $acme = Protocol::ACME->new(
        host        => 'acme-v01.api.letsencrypt.org',
        loglevel    => 'error',
        debug       => 0,
        account_key => \$account_key,
    );

    my $der_file = $self->_resolve_file_location()->{'cert_der'};
    my $tmp_ca   = $self->_resolve_file_location()->{'ca_der'};

    eval {
        $acme->directory();
        $acme->register();
        $acme->accept_tos();

        my @domains = split( /,/, $hash->{domains} );

        foreach my $domain (@domains) {
            $domain =~ s/^\s+|\s+$//g;
            $acme->authz($domain);
       
            my $challenge = Cpanel::LetsEncrypt::Challenge->new( { documentroot => $hash->{'webroot-path'}, user => $hash->{username} } );
            $acme->handle_challenge($challenge);
            $acme->check_challenge();
            $challenge->cleanup;
        }

        my $cert  = $acme->sign($csr_file);
        my $chain = $acme->chain();

        die "Could not write certificate to local disk"    if !$self->spew( $der_file, $cert );
        die "Could not write CA certificate to local disk" if !$self->spew( $tmp_ca,   $chain );

        my $conver_ca_output_ref = $self->_convert_to_crt( $tmp_ca, $ca_file );
        if ( $conver_ca_output_ref->{stderr} ) {
            die "Error occurred at line number " . __LINE__ . ': '
                . $conver_ca_output_ref->{stderr};
        }

        my $output_ref = $self->_convert_to_crt( $der_file, $cert_file );
        if ( $output_ref->{stderr} ) {
            die "Error occurred at line number " . __LINE__ . ': ' . $output_ref->{stderr};
        }
    };

    if ($@) {
        if ( ref $@ ne "Protocol::ACME::Exception" ) {
            $result_hash->{message} = $@;
        }
        else {
            $result_hash->{message} =
                "Error occurred: Status: $@->{status}, Detail: $@->{detail}, Type: $@->{type}\n";
        }
        $result_hash->{success} = '0';

        return $result_hash;
    }

    $result_hash->{success} = '1';

    return $result_hash;
}

sub create_account_key {
    my ( $self, $email ) = @_;

    my $key_file = $self->{accounts} . '/' . $email . '.key';
    return $self->slurp($key_file) if ( -e $key_file );

    my $genkey = $self->{openssl}->generate_key();

    if ( !$genkey || !$genkey->{'status'} || !$genkey->{'stdout'} ) {
        die "Key generation failed: $genkey->{'stderr'}\n";
    }

    my $key = $genkey->{'stdout'};
    $self->spew( $key_file, $key );

    return $key;
}

sub _create_csr {
    my ( $self, $hash_ref ) = @_;

    my $domain = $hash_ref->{domain};

    my $csrfile   = $self->_resolve_file_location()->{'csr'};
    my $conf_file = Cpanel::LetsEncrypt::Config->get_tmp_ssl_conf($hash_ref);

    my $output = $self->{openssl}->run(
        'args' => [
            'req', '-new', '-sha256', '-utf8',
            '-key'     => $self->_create_domain_key($domain),
            '-config'  => $conf_file,
            '-reqexts' => 'SAN',
            '-subj'    => "/",
            '-out'     => $csrfile,
        ]
    );

    if ( -e $csrfile ) {
        return $csrfile;
    }

    unlink $conf_file if -e $conf_file;
    return $output;
}

sub _create_domain_key {
    my $self   = shift;
    my $domain = shift;

    my $file = $self->_resolve_file_location()->{'key'};

    my $genkey = $self->{openssl}->generate_key();

    if ( !$genkey || !$genkey->{'status'} || !$genkey->{'stdout'} ) {
        die "Key generation failed: $genkey->{'stderr'}\n";
    }

    my $key = $genkey->{'stdout'};
    $self->spew( $file, $key );

    return $file;
}

sub _convert_to_crt {
    my ( $self, $file, $out_file ) = @_;

    if ( length $out_file && -e $out_file ) {
        unlink $out_file;    # Existence of an old key file will cause additional prompting
    }

    my $output = $self->{openssl}->run(
        'args' => [
            'x509',
            '-inform'  => 'der',
            '-outform' => 'pem',
            '-in'      => $file,
            '-out'     => $out_file
        ]
    );

    return $output;
}

sub has_active_ssl_cert {
    my $self = shift;

    my $ssl_vhosts = $self->{whm}->fetch_installed_ssl_info;

    return 1
        if ( defined $ssl_vhosts->{ $self->{domain} }
        and $ssl_vhosts->{ $self->{domain} }->{status} eq 'Active' );

    return 0;
}

sub _get_default_output_hash {
    my %output = ( 'status' => 0, 'message' => '', 'output' => '' );
    return wantarray ? %output : \%output;
}

sub slurp {
    my ( $self, $file ) = @_;

    my $content;
    if ( open( my $fh, '<', $file ) ) {
        local $/;
        $content = <$fh>;
    }

    return $content;
}

sub spew {
    my ( $self, $file, $content ) = @_;

    if ( open( my $fh, '>', $file ) ) {
        print {$fh} $content;
        close($fh);

        return 1;
    }

    return 0;
}

sub _resolve_file_location {
    my $self = shift;

    my $dir      = $self->_create_domain_dir();
    my $hash_ref = {
        'cert'     => join( '/', $dir, $self->{domain} . '.crt' ),
        'csr'      => join( '/', $dir, $self->{domain} . '.csr' ),
        'key'      => join( '/', $dir, $self->{domain} . '.key' ),
        'ca'       => join( '/', $dir, $self->{domain} . '.ca' ),
        'ca_der'   => join( '/', $dir, $self->{domain} . '_tmp_ca_.der' ),
        'cert_der' => join( '/', $dir, $self->{domain} . '_tmp_cert_.der' ),
    };

    return $hash_ref;
}

sub _create_domain_dir {
    my $self = shift;

    my $dir = $self->{domain_dir} . '/' . $self->{domain};
    if ( !-d $dir ) {
        mkdir( $dir, 0700 ) or die $!;
    }

    return $dir;
}

1;

