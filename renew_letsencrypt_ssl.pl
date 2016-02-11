#!/usr/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel};
};


use Cpanel::LetsEncrypt;
use Cpanel::LetsEncrypt::WHM;

my $log_file = '/var/letsencrypt/letsencrypt.log';

open my $fh, '>>', $log_file;

my $whm = Cpanel::LetsEncrypt::WHM->new();

my $domains = $whm->get_expired_domains;

foreach my $domain (@{$domains}) {

  next if $domain eq 'sip.prajith.in';
  
  my $result_ref = Cpanel::LetsEncrypt->new(domain => $domain)->renew_ssl_certificate();

  if ( !$result_ref->{status}  ) {
     print {$fh} "Failed to renew SSL certificate for $domain : " . $result_ref->{message} ? $result_ref->{message} : $@ . "\n";

  }
}

close($fh);
