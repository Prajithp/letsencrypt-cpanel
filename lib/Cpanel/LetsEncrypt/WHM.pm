package Cpanel::LetsEncrypt::WHM;

use strict;
use JSON ();

sub new {
    my ( $class, %opts ) = @_;

    my $self = {%opts};
    bless( $self, $class );

    $self->_init;

    return $self;
}

sub _init {
    my $self = shift;

    my $modules = {
        'Cpanel/PublicAPI.pm' => 'Cpanel::PublicAPI',
        'cPanel/PublicAPI.pm' => 'cPanel::PublicAPI',
    };

    foreach my $module ( keys %{$modules} ) {
        eval { require "$module"; };

        if ( !$@ ) {
            my $accesshash = _read_hash();
            my $username   = 'root';

            $self->{whm_api} =
                $modules->{$module}
                ->new( usessl => 0, user => $username, accesshash => $accesshash )
                or die $!;
            last;
        }
    }
}

sub get_domain_userdata {
    my ( $self, $domain ) = @_;

    my $domainuserdata = $self->liveapi_request( 'domainuserdata', { domain => $domain } );

    return ( ref $domainuserdata->{data} )
        ? $domainuserdata->{data}->{userdata}
        : $domainuserdata->{userdata};
}

sub get_domain_aliases {
    my ($self, $main_domain) = @_;

    my $json_resp = $self->get_domain_userdata( $main_domain );
    return $json_resp->{serveralias};
}

sub get_email_by_domain {
    my ( $self, $domain ) = @_;

    my $accountsummary = $self->liveapi_request( 'accountsummary', { domain => $domain } );

    return ( ref $accountsummary->{data} )
        ? $accountsummary->{data}->{acct}->[0]->{email}
        : $accountsummary->{acct}->[0]->{email};
}

sub get_expired_domains {
    my $self = shift;

    my $ssl_vhosts = $self->fetch_installed_ssl_info;
    my @domains;
    foreach my $ssl_vhost ( keys( %{$ssl_vhosts} ) ) {
        if (    $ssl_vhosts->{$ssl_vhost}->{'daysleft'} < '23'
            and $ssl_vhosts->{$ssl_vhost}->{'issuer_organizationName'} =~ m/Let's\s*Encrypt/i )
        {
            push( @domains, $ssl_vhost );
        }
    }

    return \@domains;
}

sub get_ssl_vhost_by_domain {
    my ($self, $domain) = @_;

    my $ssl_vhosts = $self->fetch_installed_ssl_info;
    
    return $ssl_vhosts->{$domain};
}

sub install_ssl_certificate {
    my ( $self, $hash_ref ) = @_;

    my $cert_file = "/var/letsencrypt/live/" . $hash_ref->{domain} . "/$hash_ref->{domain}.crt";
    my $key_file  = "/var/letsencrypt/live/" . $hash_ref->{domain} . "/$hash_ref->{domain}.key";
    my $ca_file   = "/var/letsencrypt/live/" . $hash_ref->{domain} . "/$hash_ref->{domain}.ca";

    my $cert     = $self->slurp($cert_file);
    my $key      = $self->slurp($key_file);
    my $cabundle = $self->slurp($ca_file);

    my $status = $self->liveapi_request(
        'installssl',
        {   'api.version' => '1',
            'domain'      => $hash_ref->{domain},
            'crt'         => $cert,
            'key'         => $key,
            'cab'         => $cabundle,
            'ip'          => $hash_ref->{ip_address},
        }
    );

    unless ( $status->{status} or $status->{data}->{status} ) {
        return
            wantarray
            ? ( '0', $status->{statusmsg} ? $status->{statusmsg} : $status->{data}->{statusmsg} )
            : '0';
    }

    return
        wantarray
        ? ( '1', $status->{statusmsg} ? $status->{statusmsg} : $status->{data}->{statusmsg} )
        : '1';
}

sub listaccts {
    my $self = shift;

    my @domains;
    my $ssl_vhosts   = $self->fetch_installed_ssl_info;
    my $accounts_ref = $self->liveapi_request('listaccts');
    $accounts_ref = ( ref $accounts_ref->{data} ) ? $accounts_ref->{data} : $accounts_ref;

    foreach my $acct ( @{ $accounts_ref->{acct} } ) {
        push( @domains, $acct->{domain} ) unless $ssl_vhosts->{ $acct->{domain} };

        eval {
            my $content      = $self->slurp("/var/cpanel/userdata/$acct->{user}/main");
            my $userdata_ref = Cpanel::YAML::Load($content);
            my @subdomains;
            @subdomains = @{ $userdata_ref->{sub_domains} }
                if ref $userdata_ref->{sub_domains} eq 'ARRAY';
            my @addondomains = keys %{ $userdata_ref->{addon_domains} };
            my @alt_domains = ( @subdomains, @addondomains );

            foreach my $alt_domain (@alt_domains) {
                my $main_domain =
                    $self->liveapi_request( 'domainuserdata', { domain => $alt_domain } )->{data}
                    ->{userdata}->{servername};
                next
                    if (
                    $ssl_vhosts->{$alt_domain} or grep /^$alt_domain$/,
                    @{ $ssl_vhosts->{$main_domain}->{domains} }
                    );
                push( @domains, $alt_domain );
            }
        };
    }

    return \@domains;
}

sub fetch_installed_ssl_info {
    my $self = shift;

    my $ssl_info = $self->liveapi_request( 'fetch_ssl_vhosts', { 'api.version' => '1' } );
    my $hash;

    foreach my $crt ( @{ $ssl_info->{data}->{vhosts} } ) {
        my $days_left = int( ( $crt->{crt}->{not_after} - time() ) / 86400 );

        $hash->{ $crt->{servername} } = {
            'domains'                 => $crt->{crt}->{domains},
            'not_after'               => $crt->{crt}->{not_after},
            'issuer_organizationName' => $crt->{crt}->{'issuer.organizationName'},
            'daysleft'                => $days_left,
            'status'                  => ( $days_left > '1' ) ? 'Active' : 'Expired',
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
        unless ( -f $AccessHash )
        {
            my $pid = IPC::Open3::open3( my $wh, my $rh, my $eh,
                '/usr/local/cpanel/whostmgr/bin/whostmgr setrhash' );
            waitpid( $pid, 0 );
        }
    };
    open( my $hash_fh, "<", $AccessHash ) || die "Cannot open access hash: " . $AccessHash;

    my $accesshash = do { local $/; <$hash_fh>; };
    $accesshash =~ s/\n//g;
    close($hash_fh);

    return $accesshash;
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

1;
