package Cpanel::LetsEncrypt::Config;

use strict;
use File::Temp;

sub get_tmp_ssl_conf {
    my ( $class, $hash ) = @_;

    my $domain  = $hash->{domain};
    my @SAN     = map {"DNS:$_"} split( /,/, $hash->{domains} );
    my $domains = join( ',', @SAN );

    chomp($domain);

    my $content = "[ req ]
default_bits              = 2048
distinguished_name        = req_distinguished_name
req_extensions            = req_ext
[ req_distinguished_name ]
commonName                = fqn Hostname
commonName_default        = $domain
commonName_max            = 64
[ req_ext ]
subjectAltName            = \@alt_names
[SAN]
subjectAltName            = $domains";

    my $tmp_file = File::Temp->new( UNLINK => 0, SUFFIX => '.conf' );
    my $fname = $tmp_file->filename;

    open( my $fh, '>', $fname ) or die $!;
    print {$fh} $content;
    close($fh);

    return $fname;
}

1;
