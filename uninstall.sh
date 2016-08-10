#!/bin/bash

rm -rvf /usr/local/cpanel/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt
rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/letsencrypt.pl
rm -rvf /usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/index.tt
rm -rvf /usr/local/cpanel/whostmgr/docroot/addon_plugins/ico-letsencrypt.png
rm -rvf /scripts/renew_letsencrypt_ssl.pl
cat /var/spool/cron/root | egrep -v "/scripts/renew_letsencrypt_ssl.pl" > /tmp/cron.tmp
mv -f /tmp/cron.tmp /var/spool/cron/root

/usr/local/cpanel/bin/unregister_appconfig letsencrypt

if [ -e "/usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/" ]; then
  /usr/local/cpanel/scripts/uninstall_plugin /usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/conf/letsencrypt.tar.gz
  /usr/local/cpanel/scripts/uninstall_plugin /usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/conf/letsencrypt.tar.gz --theme x3
  /usr/local/cpanel/bin/rebuild_sprites
  /usr/local/cpanel/bin/unregister_appconfig /usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/conf/letsencrypt-cpanel-ui.conf
  rm -rvf /usr/local/cpanel/base/3rdparty/letsencrypt-cpanel-ui/
fi


echo -e "\033[40m\033[001;031mSuccessfully removed  letsencrypt manager\033[0m"


