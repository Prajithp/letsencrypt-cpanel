#!/usr/local/cpanel/3rdparty/bin/perl

use lib '/usr/local/cpanel';
use Cpanel::Validate::Domain     ();
use Whostmgr::ACLS               ();
use Cpanel::LetsEncrypt          ();
use JSON                         ();
use CGI                          ();
use Template;

Whostmgr::ACLS::init_acls();

my $cgi = CGI->new();

my $cP_Datas = {
    SECURITY_TOKEN => $ENV{cp_security_token},
    WHM_USER       => $ENV{REMOTE_USER},
    WHM_PASS       => $ENV{REMOTE_PASSWORD},
    HOST           => $ENV{HTTP_HOST},
};

my $letsencrypt = Cpanel::LetsEncrypt->new();

my $vars = {
    'message'          => undef,
    'status'           => 'success',
    'version'          => $Cpanel::LetsEncrypt::VERSION,
    'installd_domains' => $letsencrypt->fetch_installed_ssl_info(),
    'domains'          => $letsencrypt->listaccts(),
    'expired_domains'  => $letsencrypt->get_expired_domains,
    format_time        => sub { return scalar localtime(shift) },
};

my $action = $cgi->param('action');

if ( $action eq 'renew' ) {
    my $domain = _sanitize( $cgi->param('domain') );

    if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain) ) {
        $vars->{message} = "Invalid Domain name";
        $vars->{status}  = "danger";

        print $cgi->header();
        build_template( 'index.tt', $vars );
        exit 0;
    }

    my $result_ref = $letsencrypt->renew_ssl_certificate($domain);

    unless ( $result_ref->{status} ) {
        $vars->{status} = 'danger';
        $vars->{message} =
            $result_ref->{message}
          ? $result_ref->{message}
          : 'Something went wrong, kindly check the letsencrypt log file';

        print $cgi->header();
        build_template( 'index.tt', $vars );
        exit 0;
    }

    $vars->{message} = $result_ref->{message};

    print $cgi->header();
    build_template( 'index.tt', $vars );
    exit 0;
}
elsif ( $action eq 'install' ) {
    my $domain = _sanitize( $cgi->param('domain') );

    if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain) ) {
        $vars->{message} = "Invalid Domain name, $domain";
        $vars->{status}  = "danger";

        print $cgi->header();
        build_template( 'index.tt', $vars );
        exit 0;
    }

    my $result_ref = $letsencrypt->activate_ssl_certificate($domain);

    unless ( $result_ref->{status} ) {
        $vars->{status} = 'danger';
        $vars->{message} =
            $result_ref->{message}
          ? $result_ref->{message}
          : 'Something went wrong, kindly check the letsencrypt log file';

        print $cgi->header();
        build_template( 'index.tt', $vars );
        exit 0;
    }

    $vars->{message} = $result_ref->{message};

    print $cgi->header();
    build_template( 'index.tt', $vars );
    exit 0;
}
else {
    $vars->{status} = undef;
    print $cgi->header();
    build_template( 'index.tt', $vars );
    exit 0;

}

sub build_template {
    my ( $file, $vars_ref ) = @_;

    my $template = Template->new(
        {
            INCLUDE_PATH => '/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt',
        }
    );

    $template->process( $file, $vars_ref )
      || die 'Template-error: ' . $template->error();

}

# copied from cPanel ip-manager plugin;
sub _sanitize {    #Sanitize input field input
    my $text = shift;
    return '' if !$text;
    $text =~ s/([;<>\*\|`&\$!?#\(\)\[\]\{\}:'"\\])/\\$1/g;
    return $text;
}
