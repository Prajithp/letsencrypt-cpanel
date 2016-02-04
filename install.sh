#!/bin/bash

if [ ! `id -u` = 0 ]; then
  echo
  echo "FAILED:::: You must login as root"
  exit 1;
fi

foundmodule=$(perl -MProtocol::ACME -e "1" 2>&1)
if [[ "$foundmodule" != "" ]]; then
  echo "Protocol::ACME is NOT installed"
  echo "Installing Protocol::ACME"
  echo "....."
  perl -MCPAN -e "install Protocol::ACME" >/dev/null 2>&1
  echo "....."
  ismodulethere=$(perl -MProtocol::ACME -e "1" 2>&1)
  if [[ "$ismodulethere" == "" ]]; then
    echo "Protocol::ACME is installed properly"
    echo "....."
  else
    echo "Protocol::ACME is NOT installed"
    echo "You can try installing these modules by running" 
    echo "/scripts/perlinstaller Protocol::ACME"
    exit 1;
  fi
fi

test -e "/var/letsencrypt" || mkdir "/var/letsencrypt"
test -e "/var/letsencrypt" || mkdir "/var/letsencrypt/conf"

if [[ -x "/usr/local/cpanel/bin/register_appconfig" ]]; then
  test -e "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/" || mkdir "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/";
  install -o root -g root -m 0755 lib/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt.pm
  /bin/cp -r  lib/Cpanel/LetsEncrypt /usr/local/cpanel/Cpanel/
  chown root.root /usr/local/cpanel/Cpanel/LetsEncrypt
  install -o root -g wheel -m 0755 cgi/letsencrypt.pl /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
  install -o root -g wheel -m 0755 cgi/index.tt /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt

  test -e "/usr/local/cpanel/whostmgr/docroot/addon_plugins" || mkdir "/usr/local/cpanel/whostmgr/docroot/addon_plugins"
  install -o root -g wheel -m 0644 icons/ico-letsencrypt.svg /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.svg
  /usr/local/cpanel/bin/register_appconfig letsencrypt_app.conf

  echo -e "\033[40m\033[001;031mSuccessfully installed letsencrypt manager\033[0m"
else
  echo -e "\033[40m\033[001;031mERROR: This addon requires 11.34 or later\033[0m"
  exit 1;
fi

