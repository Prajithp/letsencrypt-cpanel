package Cpanel::LetsEncrypt::Challenge;

use strict;
use warnings;

BEGIN {
    unshift @INC, q{/usr/local/cpanel};
}

use parent qw ( Protocol::ACME::Challenge );
use Carp;

use File::Path                           ();
use IO::Handle                           ();
use Cpanel::SafeFile                     ();
use Cpanel::AccessIds                    ();
use Cpanel::AccessIds::ReducedPrivileges ();

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self  = {};

    bless $self, $class;

    $self->_init(@_);
    return $self;
}

sub _init {
    my $self = shift;
    my $args;

    if (@_ == 1) {
        $args = shift;
        if (ref $args ne "HASH") {
            croak "Must pass a hash or hashref to challenge constructor";
        }
    }
    else {
        $args = \%_;
    }

    for my $required_arg (qw ( documentroot user )) {
        if (!exists $args->{$required_arg}) {
            croak "Require arg $required_arg missing from chalenge constructor";
        }
        else {
            $self->{$required_arg} = $args->{$required_arg};
        }
    }
}

sub handle {
    my ($self, $challenge, $fingerprint) = @_;

    my $dir  = "$self->{'documentroot'}/.well-known/acme-challenge";
    my $file = "$dir/$challenge";

    my $fh = IO::Handle->new();

    my $lock;
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            File::Path::mkpath($dir) unless -e $dir;
            $lock = Cpanel::SafeFile::safeopen($fh, '>', $file);
        },
        $self->{user}
    );

    unless (defined $lock) {
        croak "Unable to lock/open '$file': $!";
    }
    print {$fh} "$challenge.$fingerprint";
    Cpanel::SafeFile::safeclose($fh, $lock);
    return 0;
}


1;
