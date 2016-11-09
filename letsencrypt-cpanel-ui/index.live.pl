#!/usr/local/cpanel/3rdparty/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/lib/perl5};
};
    
use Cpanel::LetsEncrypt::cPanel::LiveAPI ();
use Cpanel::LetsEncrypt::cPanel          ();
use JSON                                 ();
use CGI                                  ();
use Template;  
use Data::Dumper;

my $cgi = CGI->new();

$CGI::LIST_CONTEXT_WARN = 0;

my $cpanel = Cpanel::LetsEncrypt::cPanel::LiveAPI->new();

my $vars = {
    'message'          => undef,
    'status'           => 'success',
    'installd_domains' => $cpanel->fetch_installed_ssl_info(),
    'domains'          => $cpanel->listaccts(),
    'expired_domains'  => $cpanel->get_expired_domains,
    'format_time'      => sub { return scalar localtime(shift) },
    'base_url'         => cPBase(),
    'theme'            => UserTheme(),
};

my $action   = $cgi->param('action');
my $domain   = _sanitize($cgi->param('domain'));
my $aliases  = join(',', $cgi->param('aliases'));

my $letsencrypt;
eval { $letsencrypt = Cpanel::LetsEncrypt::cPanel->new('domain' => $domain, 'aliases' => $aliases, 'api' => $cpanel) if ($domain && defined $action && $action ne 'getAliases'); };

if ($@) {
    print $cgi->header('application/text', '403 access denied');
    print $@;
    exit 1;
}

if ($action eq 'install' and defined $domain) {

    my $result_ref = $letsencrypt->get_certificate();

    unless ($result_ref->{status}) {
        $vars->{status} = 'danger';
        $vars->{message} =
              $result_ref->{message}
            ? $result_ref->{message}
            : 'Something went wrong, kindly check the letsencrypt log file';
        build_template('index.tt', $vars);
        exit 0;
    }

    $vars->{message} = $result_ref->{message};

    build_template('index.tt', $vars);
    exit 0;
}
elsif ($action eq 'getAliases') {
   my $domain_aliases = $cpanel->get_domain_aliases($domain);
   my @aliases = split / /, $domain_aliases;

   print $cgi->header('application/json');

   my $json_text = JSON::to_json(\@aliases);
   print $json_text;
   exit 0;
}

else {
    $vars->{status} = undef;

    build_template('index.tt', $vars);
    exit 0;

}

sub build_template {
    my ($file, $vars_ref) = @_;

    my $output;
    my $template =
        Template->new({INCLUDE_PATH => '/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/',});

    $template->process($file, $vars_ref, \$output) || die 'Template-error: ' . $template->error();
    if ( UserStyle() eq 'basic' ) {
        print $cpanel->cpanel_api()->header('Let&#39;s Encrypt');
        print STDOUT $output;
    }
    else {
        print $cgi->header();
        print STDOUT $output;
    }
}

# copied from cPanel ip-manager plugin;
sub _sanitize {    #Sanitize input field input
    my $text = shift;
    return '' if !$text;
    $text =~ s/([;<>\*\|`&\$!?#\(\)\[\]\{\}:'"\\])/\\$1/g;
    return $text;
}

sub UserTheme {
   my $statsbar = $cpanel->cpanel_api()->api2('StatsBar', 'stat', {"display" => "theme"});
   my $theme    = $statsbar->{'cpanelresult'}->{'data'}->['0']->{'value'};

   return $theme;
}

sub UserStyle {
    my $style = $cpanel->cpanel_api()->uapi('Styles', 'current');
    return $style->{'cpanelresult'}->{'result'}->{'data'}->{'name'};
}

sub cPBase {
    my $base_url;
    my $UserTheme = UserTheme();
    if (defined $ENV{'cp_security_token'}) {
       $base_url = $ENV{'cp_security_token'} .'/frontend/';      
    }
    else {
       $base_url = '/frontend/';
    }
    if ($UserTheme) {
        return $base_url . $UserTheme .'/';
    }
    return;
}
