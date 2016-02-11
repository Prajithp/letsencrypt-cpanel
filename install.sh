#!/bin/bash

if [ ! `id -u` = 0 ]; then
  echo
  echo "FAILED:::: You must login as root"
  exit 1;
fi

REQUIREDMODULES=( "Protocol::ACME" "JSON::XS"  "Mozilla::CA" "CGI" "cPanel::PublicAPI" )
NEEDSCHECK=()
NOTINSTALLED=()
ALLINSTALLED=1

PERLRESULT=$( perl -MCGI -e "1" 2>&1)
if [[ $PERLRESULT != "" ]]; then
  for i in "${REQUIREDMODULES[@]}"
  do
    echo "Installing $i"
    echo "....."
    /scripts/perlinstaller "$i" >/dev/null 2>&1
  done
else
  #Otherwise, test each module before install
  for i in "${REQUIREDMODULES[@]}"
  do
    foundmodule=$(perl -M$i -e "1" 2>&1)
    if [[ "$foundmodule" != "" ]]; then
      echo "$i is NOT installed"
      echo "Installing $i"
      echo "....."
      /scripts/perlinstaller "$i" >/dev/null 2>&1
      echo "....."
      NEEDSCHECK=( "${NEEDSCHECK[@]}" "$i" ) #prevent unset issues with array -1
    fi
  done
fi
SIZEOFNEEDS=${#NEEDSCHECK[@]}
if [[ "$SIZEOFNEEDS" -ge "1" ]]; then
  echo "$GREEN Testing  perl modules we just installed $RESET"
  echo "....."
  for i in "${NEEDSCHECK[@]}"
  do
    ismodulethere=$(perl -M$i -e "1" 2>&1)
    if [[ "$ismodulethere" == "" ]]; then
      echo "$i is installed properly"
      echo "....."
    else
      echo "$i is NOT installed"
      echo "....."
      ALLINSTALLED=0
      NOTINSTALLED=( "${NOTINSTALLED[@]}" "$i" )
    fi
  done
fi

if [[ "$ALLINSTALLED" != 1 ]]; then
  echo "There was an error verifying  required perl modules are installed."
  echo "The following perl modules could not be installed: "
  for i in "${NOTINSTALLED[@]}"
  do
    echo "$i"
  done
  echo "You can try installing these modules by running" 
  echo "/scripts/perlinstaller <module_name>"
  echo "for each module name listed above."
  exit 1
else
  echo ".....DONE"
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
  cp -r renew_letsencrypt_ssl.pl /scripts/renew_letsencrypt_ssl.pl
  chmod 700 /scripts/renew_letsencrypt_ssl.pl
  crontab -l > /tmp/crontab.tmp
  echo "00 00 * * *  /scripts/renew_letsencrypt_ssl.pl" >> /tmp/crontab.tmp
  crontab /tmp/crontab.tmp
  rm -rf /tmp/crontab.tmp

  echo -e "\033[40m\033[001;031mSuccessfully installed letsencrypt manager\033[0m"
else
  echo -e "\033[40m\033[001;031mERROR: This addon requires 11.34 or later\033[0m"
  exit 1;
fi

