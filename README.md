## letsencrypt-cpanel
 cPanel/WHM plugin for Let's Encrypt client (uses Perl and WHM API) 

# Known issue
* letsencrypt client requires python 2.7 (https://github.com/letsencrypt/letsencrypt/issues/110669).
    For centos 6, you can install python 2.7 via IUS Community yum repo https://ius.io/GettingStarted/261



# Installation
```
/usr/local/cpanel/3rdparty/bin/git clone https://github.com/Prajithp/letsencrypt-cpanel.git
cd letsencrypt-cpanel
./install.sh
```
If everything goes well, you can see an icon in the WHM >> Plugins Section

* Please, do not contact me by email, I won't answer your questions. For developing matters you can open an issue, create a pull request or (in case you think it's necessary) email me.
