#!/usr/local/cpanel/3rdparty/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/lib/perl5};
};


use Cpanel::LetsEncrypt;
use Cpanel::LetsEncrypt::WHM;
use Cpanel::LetsEncrypt::Service;

my $log_file = '/var/letsencrypt/letsencrypt.log';

open my $fh, '>>', $log_file;

my $whm = Cpanel::LetsEncrypt::WHM->new();
my $service = Cpanel::LetsEncrypt::Service->new();

my @services = ('exim', 'dovecot', 'cpanel', 'ftp');

my $domains = $whm->get_expired_domains;

foreach my $domain (@{$domains}) {

  my $result_ref; 
  eval { $result_ref = Cpanel::LetsEncrypt->new(domain => $domain)->renew_ssl_certificate(); };
 
  if ($@) {
    print {$fh} "Failed to renew SSL certificate for $domain : " . $@ . "\n";
  }  

  if ( !$result_ref->{status} ) {
     print {$fh} "Failed to renew SSL certificate for $domain : " . $result_ref->{message} ? $result_ref->{message} : $@ . "\n";

  }
}

eval { $service->check_for_expiry; };
if ($@) {
    print {$fh} "Failed to renew SSL certificate for hostname : " . $@ . "\n";
}

close($fh);
