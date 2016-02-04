#!/usr/bin/perl

use lib '/usr/local/cpanel';
use Whostmgr::ACLS           ();
use Cpanel::LetsEncrypt      ();
use Cpanel::LetsEncrypt::WHM ();
use JSON                     ();
use CGI                      ();
use Template;

Whostmgr::ACLS::init_acls();

my $cgi = CGI->new();

if (!Whostmgr::ACLS::hasroot()) {
  print $cgi->header('application/text', '400 Bad request');
  print 'Access denied';
  exit 1;
}

my $cP_Datas = {SECURITY_TOKEN => $ENV{cp_security_token}, WHM_USER => $ENV{REMOTE_USER}, WHM_PASS => $ENV{REMOTE_PASSWORD}, HOST => $ENV{HTTP_HOST},};

my $whm         = Cpanel::LetsEncrypt::WHM->new();

my $vars = {
  'message'          => undef,
  'status'           => 'success',
  'version'          => $Cpanel::LetsEncrypt::VERSION,
  'installd_domains' => $whm->fetch_installed_ssl_info(),
  'domains'          => $whm->listaccts(),
  'expired_domains'  => $whm->get_expired_domains,
  'format_time'      => sub { return scalar localtime(shift) },
};

my $action = $cgi->param('action');
my $domain = _sanitize($cgi->param('domain'));

my $letsencrypt = Cpanel::LetsEncrypt->new(domain => $domain) if ( defined $domain && defined $action );

if ($action eq 'renew' and defined $domain) {

  my $result_ref = $letsencrypt->renew_ssl_certificate();

  unless ($result_ref->{status}) {
    $vars->{status} = 'danger';
    $vars->{message} = $result_ref->{message} ? $result_ref->{message} : 'Something went wrong, kindly check the letsencrypt log file';

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
    $vars->{message} = $result_ref->{message} ? $result_ref->{message} : 'Something went wrong, kindly check the letsencrypt log file';

    print $cgi->header();
    build_template('index.tt', $vars);
    exit 0;
  }

  $vars->{message} = $result_ref->{message};

  print $cgi->header();
  build_template('index.tt', $vars);
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

  my $template = Template->new({INCLUDE_PATH => '/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt',});

  $template->process($file, $vars_ref) || die 'Template-error: ' . $template->error();

}

# copied from cPanel ip-manager plugin;
sub _sanitize {    #Sanitize input field input
  my $text = shift;
  return '' if !$text;
  $text =~ s/([;<>\*\|`&\$!?#\(\)\[\]\{\}:'"\\])/\\$1/g;
  return $text;
}
