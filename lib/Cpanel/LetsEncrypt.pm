package Cpanel::LetsEncrypt;

use JSON              ();
use IPC::Open3        ();
use File::Temp        ();
use Data::Dumper      ();
use Cpanel::YAML      ();

our $VERSION = '1.0.0';

sub new {
    my ( $class, %opts ) = @_;

    my $self = {%opts};

    $self->{work_dir}   = '/var/letsencrypt';
    $self->{config_dir} = $self->{work_dir} . '/conf';
    $self->{letsencrypt} ||= '/usr/local/letsencrypt/letsencrypt-auto';

    bless( $self, $class );

    $self->_init;

    return $self;
}

sub _init {
    my $self = shift;

    for my $dir ( $self->{work_dir}, $self->{config_dir} ) {
        mkdir $dir unless -d $dir;
    }

    my $accesshash = _read_hash();
    my $username   = 'root';

    my $modules = {
          'Cpanel/PublicAPI.pm' => 'Cpanel::PublicAPI',
          'cPanel/PublicAPI.pm' => 'cPanel::PublicAPI',
    };

    foreach my $module (keys %{$modules}) {
        eval { require "$module"; };

        if ( !$@ ) {
            $self->{whm_api} = $modules->{$module}->new(
                usessl     => 0,
                user       => $username,
                accesshash => $accesshash
            ) or die $!;

            last;
        }
    }
}

sub activate_ssl_certificate {
    my $self = shift;
    my $domain = shift || $self->{domain};

    my $return_vars = {
        status  => '0',
        message => '',
    };

    $self->{domain} = $domain unless defined $self->{domain};

    unless ( defined $self->{domain} ) {
        $return_vars->{message} = "You must provide atleast one domain name";
        return $return_vars;
    }

    if ( $self->has_active_ssl_cert ) {
        $return_vars->{message} =
"The domain $self->{domain} is already having an active ssl certificate";
        return $return_vars;
    }

    my $json_resp =
      $self->liveapi_request( 'domainuserdata', { domain => $self->{domain} } );

    my $email =
      $self->liveapi_request( 'accountsummary', { domain => $self->{domain} } )
      ->{acct}->[0]->{email};

    my $aliases = $json_resp->{userdata}->{serveralias};
    $aliases =~ s/\s+/\,/g;

    unless ($email) {
        $return_vars->{message} =
          "Update the domain owner email id in whm first";
        return $return_vars;
    }

    my $hash;
    if ( $json_resp->{result}[0]->{status} ) {
        $hash = {
            'rsa-key-size'  => '4096',
            'authenticator' => 'webroot',
            'webroot-path'  => $json_resp->{userdata}->{documentroot},
            'server'        => 'https://acme-v01.api.letsencrypt.org/directory',
            'renew-by-default' => 'True',
            'agree-tos'        => 'True',
            'ip_address'       => $json_resp->{userdata}->{ip},
            'email'            => $email,
            'domains'          => "$self->{domain}, $aliases",
            'username'         => $json_resp->{userdata}->{user},
        };
    }

    my $tmp_file = $self->create_letsencrypt_conf($hash);
    my $status   = $self->_request_for_ssl_cert($tmp_file);

    unless ( $status->{success} ) {
        $return_vars->{message} = $status->{message};
        return $return_vars;
    }

    $hash->{expire_at} = $status->{expire_at};

    my ( $ok, $message ) = $self->install_ssl_certificate($hash);

    unless ($ok) {
        $return_vars->{message} =
            $message
          ? $message
          : "cPanel SSL installation failed, please check the log file for more info";
        return $install_status;
    }

    $self->store_as_json($hash);

    $return_vars->{status}  = '1';
    $return_vars->{message} = 'Successfully installed ssl certificate';

    return $return_vars;
}

sub get_expired_domains {
    my $self = shift;

    my $ssl_vhosts = $self->fetch_installed_ssl_info;

    my @domains;
    foreach my $ssl_vhost ( keys( %{$ssl_vhosts} ) ) {
        if (    $ssl_vhosts->{$ssl_vhost}->{daysleft} < '5'
            and $ssl_vhosts->{$ssl_vhost}->{issuer_organizationName} =
            "Let's Encrypt" )
        {
            push( @domains, $ssl_vhost );
        }
    }

    return \@domains;
}

sub renew_ssl_certificate {
    my $self = shift;
    my $domain = shift || $self->{domain};

    my $return_vars = {
        status  => '0',
        message => '',
    };

    $self->{domain} = $domain unless defined $self->{domain};

    unless ( defined $self->{domain} ) {
        $return_vars->{message} = "You must provide atleast one domain name";
        return $return_vars;
    }

    my @expired_domains = $self->get_expired_domains;

    unless ( grep /^$self->{domain}/i, @expired_domains ) {
        $return_vars->{message} = "Could not find the domain in expired list";
        return $return_vars;
    }

    my $config_file = $self->{config_dir} . '/' . $self->{domain} . '.json';
    unless ( -e $config_file ) {
        $return_vars->{message} =
"Could not find the domain config file, please revoke the ssl cert and install it again";
        return $return_vars;
    }

    my $hash     = $self->read_as_hash($config_file);
    my $tmp_file = $self->create_letsencrypt_conf($hash);
    my $status   = $self->_request_for_ssl_cert($tmp_file);

    unless ( $status->{success} ) {
        $return_vars->{message} = $status->{message};
        return $return_vars;
    }

    $hash->{expire_at} = $status->{expire_at};

    my ( $ok, $message ) = $self->install_ssl_certificate($hash);

    unless ($ok) {
        $return_vars->{message} =
            $message
          ? $message
          : "cPanel SSL installation failed, please check the log file for more info";
        return $install_status;
    }

    $self->store_as_json($hash);

    $return_vars->{status} = '1';
    $return_vars->{message} =
      $message ? $message : 'Successfully installed ssl certificate';

    return $return_vars;
}

sub read_as_hash {
    my ( $self, $file ) = @_;

    my $content = $self->slurp($file);

    return JSON::decode_json($content);
}

sub store_as_json {
    my ( $self, $content ) = @_;

    my $file = $self->{config_dir} . '/' . $self->{domain} . '.json';
    if ( open( my $rh, '>', $file ) ) {
        print $rh JSON::encode_json($content);
        close($rh);

        return 1;
    }

    return 0;
}

sub create_letsencrypt_conf {
    my ( $self, $hash_ref ) = @_;

    my $tmp_file = File::Temp->new( UNLINK => 0, SUFFIX => '.conf' );
    my $fname = $tmp_file->filename;

    open( my $fh, '>>', $fname )
      or die "Can't create tmp file for writing letsencrypt conf";

    for my $key (
        qw/rsa-key-size authenticator webroot-path server renew-by-default agree-tos email domains/
      )
    {
        print $fh "$key = $hash_ref->{$key}" . "\n";
    }

    close($fh);

    return $fname;
}

sub _request_for_ssl_cert {
    my ( $self, $file ) = @_;

    my $result_hash = {
        'message'   => '',
        'success'   => '0',
        'expire_at' => ''
    };

    my $command =
      "$self->{letsencrypt} certonly --config $file --renew-by-default";

    my $result = $self->executeForkedTask($command);

    $result_hash->{message} = $result;

    if ( $result =~ m/Your\s*cert\s*will\s*expire\s*on\s*([0-9-]+)/i ) {
        $result_hash->{expire_at} = $1;
        $result_hash->{success}   = '1';
    }

    unlink $file if -e $file;

    return $result_hash;
}

sub install_ssl_certificate {
    my ( $self, $hash_ref ) = @_;

    my $cert_file = "/etc/letsencrypt/live/" . $self->{domain} . "/cert.pem";
    my $key_file  = "/etc/letsencrypt/live/" . $self->{domain} . "/privkey.pem";
    my $ca_file   = "/etc/letsencrypt/live/" . $self->{domain} . "/chain.pem";

    my $cert     = $self->slurp($cert_file);
    my $key      = $self->slurp($key_file);
    my $cabundle = $self->slurp($ca_file);

    my $status = $self->liveapi_request(
        'installssl',
        {
            'api.version' => '1',
            'domain'      => $self->{domain},
            'crt'         => $cert,
            'key'         => $key,
            'cab'         => $cabundle,
            'ip'          => $hash_ref->{ip_address},
        }
    );

    unless ( $status->{status} or $status->{data}->{status} ) {
        return wantarray
          ? (
            '0',
            $status->{statusmsg}
            ? $status->{statusmsg}
            : $status->{data}->{statusmsg}
          )
          : '0';
    }

    return wantarray
      ? (
        '1',
        $status->{statusmsg}
        ? $status->{statusmsg}
        : $status->{data}->{statusmsg}
      )
      : '1';
}

sub has_active_ssl_cert {
    my $self = shift;

    return 1 if -e $self->{config_dir} . '/' . $self->{domain} . '.json';

    my $ssl_vhosts = $self->fetch_installed_ssl_info;

    return 1
      if ( defined $ssl_vhosts->{ $self->{domain} }
        and $ssl_vhosts->{ $self->{domain} }->{status} eq 'Active' );

    return 0;
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

sub executeForkedTask {
    my ( $self, $command ) = @_;

    my ( $eh, $rh, $pid, $result, $wh );
    $pid = IPC::Open3::open3( $wh, $rh, $eh, $command );
    {
        local $/;
        $result = readline($rh);
        $result =~ s/[\n]+//g;
    }

    waitpid( $pid, 0 );
    return $result || '';
}

sub listaccts {
    my $self = shift;

    my @domains;
    my $ssl_vhosts   = $self->fetch_installed_ssl_info;
    my $accounts_ref = $self->liveapi_request('listaccts');

    foreach my $acct ( @{ $accounts_ref->{acct} } ) {
        push( @domains, $acct->{domain} )
          unless $ssl_vhosts->{ $acct->{domain} };

        {
            my $content =
              $self->slurp("/var/cpanel/userdata/$acct->{user}/main");
            my $subdomain_ref = Cpanel::YAML::Load($content);
            foreach my $subdomain ( @{ $subdomain_ref->{sub_domains} } ) {
                next if $ssl_vhosts->{$subdomain};
                push( @domains, $subdomain );
            }
        }
    }

    return \@domains;
}

sub fetch_installed_ssl_info {
    my $self = shift;

    my $ssl_info =
      $self->liveapi_request( 'fetch_ssl_vhosts', { 'api.version' => '1' } );
    my $hash;

    foreach my $crt ( @{ $ssl_info->{data}->{vhosts} } ) {
        my $days_left = int( ( $crt->{crt}->{not_after} - time() ) / 86400 );

        $hash->{ $crt->{servername} } = {
            'domains'   => $crt->{crt}->{domains},
            'not_after' => $crt->{crt}->{not_after},
            'issuer_organizationName' =>
              $crt->{crt}->{'issuer.organizationName'},
            'daysleft' => $days_left,
            'status'   => ( $days_left > '1' ) ? 'Active' : 'Expired',
        };
    }

    return $hash;
}

sub liveapi_request {
    my ( $self, $func, $opts ) = @_;

    $opts = {} unless ( ref $opts eq 'HASH' );

    my $response = $self->{whm_api}->whm_api( $func, $opts, 'json' );

    my $json = JSON->new->allow_nonref->utf8->relaxed->decode($response);

    return $json;
}

sub _read_hash() {
    my $AccessHash = "/root/.accesshash";

  eval {
    unless ( -f $AccessHash ) {
        my $pid = IPC::Open3::open3( my $wh, my $rh, my $eh,
            '/usr/local/cpanel/whostmgr/bin/whostmgr setrhash' );
        waitpid( $pid, 0 );
    }
  };
    open( my $hash_fh, "<", $AccessHash )
      || die "Cannot open access hash: " . $AccessHash;

    my $accesshash = do { local $/; <$hash_fh>; };
    $accesshash =~ s/\n//g;
    close(my $hash_fh);

    return $accesshash;

}

1;
