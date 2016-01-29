#!/bin/bash

if [[ -e "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl" ]]; then

  rm -rvf /usr/local/cpanel/Cpanel/LetsEncrypt.pm
  rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
  rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt
  rm -rvf /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.svg

  install -o root -g root -m 0755 lib/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt.pm
  install -o root -g wheel -m 0755 cgi/letsencrypt.pl /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
  install -o root -g wheel -m 0755 cgi/index.tt /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt

  install -o root -g wheel -m 0644 icons/ico-letsencrypt.svg /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.svg
  /usr/local/cpanel/bin/register_appconfig letsencrypt_app.conf

  echo -e "\033[40m\033[001;031mSuccessfully updated letsencrypt manager\033[0m"
  exit 1;
fi

