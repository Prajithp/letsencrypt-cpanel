#!/bin/bash

letsencrypt_dir="/usr/local/letsencrypt"
cwd=$(pwd)
os_version="$(rpm -q --qf %{version} `rpm -q --whatprovides redhat-release` | cut -c 1)"

if [ ! `id -u` = 0 ]; then
  echo
  echo "FAILED:::: You must login as root"
  exit 1;
fi

if [ ! -e "/usr/bin/python2.7" ]; then
  if [ ${os_version} -eq '6' ]; then
    rpm -ivh https://rhel6.iuscommunity.org/ius-release.rpm
    rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm

    yum install -y python27 python27-devel python27-pip python27-setuptools python27-virtualenv --enablerepo=ius

    if [[ ! -e "/usr/bin/python2.7" ]]; then
      echo -e "\033[40m\033[001;031mERROR: python27 installation  failed, please install the same and try again \033[0m"
      exit 1
    fi
  else
     echo -e "\033[40m\033[001;031mERROR: Please install python 2.7 manually and re-run this script \033[0m"
     exit 1;
  fi
fi

test -e "/var/letsencrypt" || mkdir "/var/letsencrypt"
test -e "/var/letsencrypt" || mkdir "/var/letsencrypt/conf"

if [[ ! -e "${letsencrypt_dir}/letsencrypt-auto" ]]; then
  cd /usr/local

  /usr/local/cpanel/3rdparty/bin/git clone https://github.com/letsencrypt/letsencrypt
  cd ${cwd}

  sed -i "s|--python python2|--python python2.7|" ${letsencrypt_dir}/letsencrypt-auto

  /usr/local/letsencrypt/letsencrypt-auto --verbose >/dev/null 2&>1
fi

if [[ -x "/usr/local/cpanel/bin/register_appconfig" ]]; then
  test -e "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/" || mkdir "/usr/local/cpanel/whostmgr/docroot/cgi/letsencrypt/";
  install -o root -g root -m 0755 lib/Cpanel/LetsEncrypt.pm /usr/local/cpanel/Cpanel/LetsEncrypt.pm
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

