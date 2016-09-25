package Cpanel::LetsEncrypt::cPanel::LiveAPI;

use Cpanel::LiveAPI ();

sub new {
    my $class = shift;

    my $self = {};

    bless( $self, $class );

    $self->{api} = Cpanel::LiveAPI->new();

    return $self;
}

sub cpanel_api {
    my $self = shift;

    $self->{api} ||= Cpanel::LiveAPI->new();

    return $self->{api};
}

sub get_home_dir {
    my $self = shift;

    return $ENV{'HOME'};
}

sub get_ssl_vhost_by_domain {
    my ($self, $domain) = @_;

    my $ssl_vhosts = $self->fetch_installed_ssl_info;

    return $ssl_vhosts->{$domain};
}

sub get_domain_aliases {
    my ($self, $main_domain) = @_;

    my $json_resp = $self->get_domain_userdata( $main_domain );
    return $json_resp->{serveralias};
}


sub fetch_installed_ssl_info {
    my $self = shift;

    my $SSL_installed_hosts = $self->{api}->uapi( 'SSL', 'installed_hosts', );
    my $hash;

    foreach my $crt ( @{ $SSL_installed_hosts->{'cpanelresult'}->{'result'}->{data} } ) {
        my $days_left = int( ( $crt->{'certificate'}->{not_after} - time() ) / 86400 );

        $hash->{ $crt->{servername} } = {
            'domains'                 => $crt->{'certificate'}->{domains},
            'not_after'               => $crt->{'certificate'}->{not_after},
            'issuer_organizationName' => $crt->{'certificate'}->{'issuer.organizationName'},
            'daysleft'                => $days_left,
            'status'                  => ( $days_left > '1' ) ? 'Active' : 'Expired',
        };

    }

    return $hash;
}

sub get_expired_domains {
    my $self = shift;

    my $ssl_vhosts = $self->fetch_installed_ssl_info;

    my @domains;
    foreach my $ssl_vhost ( keys( %{$ssl_vhosts} ) ) {
        if (    $ssl_vhosts->{$ssl_vhost}->{'daysleft'} < '5'
            and $ssl_vhosts->{$ssl_vhost}->{'issuer_organizationName'} =~ m/Let's\s*Encrypt/i )
        {
            push( @domains, $ssl_vhost );
        }
    }

    return \@domains;
}

sub listaccts {
    my $self = shift;

    my @domains;
    my @alt_domains;
    my $ssl_vhosts  = $self->fetch_installed_ssl_info;
    my $listdomains = $self->{api}->uapi( 'DomainInfo', 'list_domains' );
    my $account_ref = $listdomains->{'cpanelresult'}->{'result'}->{'data'};
    push( @domains, $account_ref->{'main_domain'} )
        if !$ssl_vhosts->{ $account_ref->{'main_domain'} };

    push( @alt_domains, @{ $account_ref->{'addon_domains'} } );
    push( @alt_domains, @{ $account_ref->{'sub_domains'} } );

    foreach my $alt_domain (@alt_domains) {
        my $main_domain =
            $self->{api}->uapi( 'DomainInfo', 'single_domain_data', { 'domain' => $alt_domain } )
            ->{'cpanelresult'}->{'result'}->{'data'}->{'servername'};
        next
            if (
            $ssl_vhosts->{$alt_domain} or grep /^$alt_domain$/,
            @{ $ssl_vhosts->{$main_domain}->{domains} }
            );
        push( @domains, $alt_domain );
    }

    return \@domains;
}

sub get_domains_list {
    my $self = shift;

    my @domains;
    my $listdomains = $self->{api}->uapi( 'DomainInfo', 'list_domains' );
    my $account_ref = $listdomains->{'cpanelresult'}->{'result'}->{'data'};

    push( @domains, $account_ref->{'main_domain'} );
    push( @domains, @{ $account_ref->{'addon_domains'} } );
    push( @domains, @{ $account_ref->{'sub_domains'} } );

    return \@domains;
}

sub get_domain_userdata {
    my ( $self, $domain ) = @_;

    my $domainuserdata =
        $self->{'api'}->uapi( 'DomainInfo', 'single_domain_data', { 'domain' => $domain } );

    return $domainuserdata->{'cpanelresult'}->{'result'}->{'data'};
}

sub install_ssl_certificate {
    my ( $self, $hash_ref ) = @_;

    my $homedir  = $self->get_home_dir();
    my $main_dir = $homedir . '/.letsencrypt/live/';

    my $cert_file = $main_dir . $hash_ref->{domain} . "/$hash_ref->{domain}.crt";
    my $key_file  = $main_dir . $hash_ref->{domain} . "/$hash_ref->{domain}.key";
    my $ca_file   = $main_dir . $hash_ref->{domain} . "/$hash_ref->{domain}.ca";

    my $cert     = $self->slurp($cert_file);
    my $key      = $self->slurp($key_file);
    my $cabundle = $self->slurp($ca_file);

    my $status = $self->{'api'}->uapi(
        'SSL',
        'install_ssl',
        {   'domain'   => $hash_ref->{domain},
            'cert'     => $cert,
            'key'      => $key,
            'cabundle' => $cabundle,
        }
    );

    return $status;
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
