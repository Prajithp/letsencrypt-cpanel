#!/bin/bash

if [[ -e "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl" ]]; then

  rm -rvf /usr/local/cpanel/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt
  rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
  rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt
  rm -rvf /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.svg
  rm -rvf /scripts/renew_letsencrypt_ssl.pl

  test -e "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/" || mkdir "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/";
  install -o root -g root -m 0755 lib/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt.pm
  /bin/cp -r  lib/Cpanel/LetsEncrypt /usr/local/cpanel/Cpanel/
  chown root.root /usr/local/cpanel/Cpanel/LetsEncrypt
  install -o root -g wheel -m 0755 cgi/letsencrypt.pl /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
  install -o root -g wheel -m 0755 cgi/index.tt /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt

  test -e "/usr/local/cpanel/whostmgr/docroot/addon_plugins" || mkdir "/usr/local/cpanel/whostmgr/docroot/addon_plugins"
  install -o root -g wheel -m 0644 icons/ico-letsencrypt.svg /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.svg
  /usr/local/cpanel/bin/register_appconfig letsencrypt_app.conf
  cp -r renew_letsencrypt_ssl.pl  /scripts/renew_letsencrypt_ssl.pl
  chmod 755 /scripts/renew_letsencrypt_ssl.pl

  echo -e "\033[40m\033[001;031mSuccessfully updated letsencrypt manager\033[0m"
  exit 1;
fi

