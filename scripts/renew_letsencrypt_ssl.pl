#!/usr/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/lib/perl5};
};


use Cpanel::LetsEncrypt;
use Cpanel::LetsEncrypt::WHM;
use Cpanel::LetsEncrypt::Service;
use Cpanel::iContact;

my $log_file = '/var/letsencrypt/letsencrypt.log';

open my $fh, '>>', $log_file;

my $whm = Cpanel::LetsEncrypt::WHM->new();
my $service = Cpanel::LetsEncrypt::Service->new();

my @services = ('exim', 'dovecot', 'cpanel', 'ftp');

my $domains = $whm->get_expired_domains;

foreach my $domain (@{$domains}) {

  my $result_ref; 
  my $is_installed  = '1';
  my $error_message = undef;
  my $username      = $whm->get_domain_userdata($domain)->{'user'};

  eval { $result_ref = Cpanel::LetsEncrypt->new(domain => $domain)->renew_ssl_certificate(); };
 
  if ($@) {
    $is_installed  = '0';
    $error_message = $@;

    print {$fh} "Failed to renew SSL certificate for $domain : " . $error_message . "\n";
  }  

  if ( !$result_ref->{status} ) {
     $is_installed  = '0';
     $error_message = $result_ref->{message};

     print {$fh} "Failed to renew SSL certificate for $domain : " . $result_ref->{message} ? $result_ref->{message} : $@ . "\n";
  }

  if (!$is_installed) {
     my %args = (
         'subject'  => 'LetsEncrypt renewal notice',
         'to'       => $username,
         'message'  => "Failed to renew SSL certificate for $domain\n\nError: $error_message",
         'prepend_domain_subject' => '1',
         'quit'     => '1',
     ); 
     eval { Cpanel::iContact::icontact(%args); };
  }
  else {
     my %args = (
         'subject'  => 'Lets Encrypt renewal notice',
         'to'       => $username,
         'message'  => "Successfully renewed SSL certificate for $domain",
         'prepend_domain_subject' => '1',
         'quit'     => '1',
     );
     eval { Cpanel::iContact::icontact(%args); };
  }  
}

eval { $service->check_for_expiry; };
if ($@) {
    print {$fh} "Failed to renew SSL certificate for hostname : " . $@ . "\n";
}

close($fh);
