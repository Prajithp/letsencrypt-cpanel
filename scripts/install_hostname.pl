#!/usr/bin/perl

BEGIN {
    unshift @INC, q{/usr/local/cpanel};
};


use Cpanel::LetsEncrypt::Service;
use Data::Dumper;

my $service = Cpanel::LetsEncrypt::Service->new();

my @services = ('exim', 'dovecot', 'cpanel', 'ftp');

#print Dumper $service->get_certificate();
#print Dumper $service->install_cert_for_service(\@services);
print Dumper $service->check_for_expiry;
