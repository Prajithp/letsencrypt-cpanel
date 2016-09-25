#!/usr/local/cpanel/3rdparty/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/lib/perl5};
};

use Whostmgr::ACLS               ();
use Cpanel::LetsEncrypt          ();
use Cpanel::LetsEncrypt::WHM     ();
use Cpanel::LetsEncrypt::Service ();
use JSON                         ();
use CGI                          ();
use Template;
use Data::Dumper;

$CGI::LIST_CONTEXT_WARN = 0;

Whostmgr::ACLS::init_acls();

my $cgi = CGI->new();

if (!Whostmgr::ACLS::hasroot()) {
    print $cgi->header('application/text', '400 Bad request');
    print 'Access denied';
    exit 1;
}

my $cP_Datas = {
    SECURITY_TOKEN => $ENV{cp_security_token},
    WHM_USER       => $ENV{REMOTE_USER},
    WHM_PASS       => $ENV{REMOTE_PASSWORD},
    HOST           => $ENV{HTTP_HOST},
};

my $whm = Cpanel::LetsEncrypt::WHM->new();

my $vars = {
    'message'          => undef,
    'status'           => 'success',
    'version'          => $Cpanel::LetsEncrypt::VERSION,
    'installd_domains' => $whm->fetch_installed_ssl_info(),
    'domains'          => $whm->listaccts(),
    'expired_domains'  => $whm->get_expired_domains,
    'format_time'      => sub { return scalar localtime(shift) },
};

my $action   = scalar $cgi->param('action');
my $domain   = _sanitize(scalar $cgi->param('domain'));
my $aliases  = join(',', $cgi->param('aliases'));
my @services = $cgi->param('services[]');

my $letsencrypt = Cpanel::LetsEncrypt->new(domain => $domain, aliases => $aliases)
    if (defined $domain && defined $action and $action ne 'service' and $action ne 'getAliases');

if ($action eq 'renew' and defined $domain) {

    my $result_ref = $letsencrypt->renew_ssl_certificate();

    unless ($result_ref->{status}) {
        $vars->{status} = 'danger';
        $vars->{message} =
              $result_ref->{message}
            ? $result_ref->{message}
            : 'Something went wrong, kindly check the letsencrypt log file';

        print $cgi->header();
        build_template('index.tt', $vars);
        exit 0;
    }

    $vars->{message} = $result_ref->{message};

    print $cgi->header();
    build_template('index.tt', $vars);
    exit 0;
}
elsif ($action eq 'install' and defined $domain) {

    my $result_ref = $letsencrypt->activate_ssl_certificate();

    unless ($result_ref->{status}) {
        $vars->{status} = 'danger';
        $vars->{message} =
              $result_ref->{message}
            ? $result_ref->{message}
            : 'Something went wrong, kindly check the letsencrypt log file';

        print $cgi->header();
        build_template('index.tt', $vars);
        exit 0;
    }

    $vars->{'installd_domains'} = $whm->fetch_installed_ssl_info();
    $vars->{'domains'} =  $whm->listaccts();
    $vars->{message} = $result_ref->{message};

    print $cgi->header();
    build_template('index.tt', $vars);
    exit 0;
}
elsif ($action eq 'service') {
    my $ssl_for_services = Cpanel::LetsEncrypt::Service->new();

    my $output_ref = $ssl_for_services->get_certificate();
    if (!$output_ref->{success}) {
        $vars->{status}  = 'danger';
        $vars->{message} = $output_ref->{message};

        print $cgi->header();
        build_template('index.tt', $vars);
        exit 0;
    }
   
    my ($ok, $message) = $ssl_for_services->install_cert_for_service(\@services);
    if (!$ok) {
       $vars->{status}  = 'danger';
       $vars->{message} = $message;
   
       print $cgi->header();
       build_template('index.tt', $vars);
       exit 0;
    }

    $vars->{message} = "Installed certificate for cPanel/WHM services, please restart 'cpsrvd' daemon using '/scripts/restartsrv_cpsrvd'";
    print $cgi->header();
    build_template('index.tt', $vars);
    exit 0;
}
elsif ($action eq 'getAliases') {
   my $domain_aliases = $whm->get_domain_aliases($domain);
   my @aliases = split / /, $domain_aliases;

   print $cgi->header('application/json');

   my $json_text = JSON::to_json(\@aliases);
   print $json_text;
   exit 0;
}
else {
    $vars->{status} = undef;
    print $cgi->header();
    build_template('index.tt', $vars);
    exit 0;

}

sub build_template {
    my ($file, $vars_ref) = @_;

    my $template =
        Template->new({INCLUDE_PATH => '/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt',});

    $template->process($file, $vars_ref) || die 'Template-error: ' . $template->error();

}

# copied from cPanel ip-manager plugin;
sub _sanitize {    #Sanitize input field input
    my $text = shift;
    return '' if !$text;
    $text =~ s/([;<>\*\|`&\$!?#\(\)\[\]\{\}:'"\\])/\\$1/g;
    return $text;
}
