#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.

# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

PACKAGES=( bash )

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

### Compile Google Authenticator
yum remove google-authenticator -y;
yum install git-core qrencode pam-devel make gcc wget autoreconf unzip autoconf automake libtool -y;

git clone https://github.com/google/google-authenticator-libpam.git

[[ -d '/opt/googleAuthenticator' ]] && rm -rf /opt/googleAuthenticator
mkdir -pv /opt/googleAuthenticator

./bootstrap.sh ;
./configure  --prefix=/opt/googleAuthenticator ;
make && make install ;

# Install Google Authenticator
unlink /usr/bin/google-authenticator ;
unlink /lib64/security/pam_google_authenticator.so ;
unlink /lib64/security/pam_google_authenticator.la ;
ln -s /usr/local/bin/google-authenticator /usr/bin/google-authenticator ;
ln -s /usr/local/lib/security/pam_google_authenticator.so /lib64/security/pam_google_authenticator.so ;
ln -s /usr/local/lib/security/pam_google_authenticator.la /lib64/security/pam_google_authenticator.la ;

# Config SSH Daemon
sed -i '/#%PAM/a auth\ \ \ \ \ \ \ required\ \ \ \ \ pam_google_authenticator.so nullok' /etc/pam.d/sshd ;
sed -i 's/#PermitRootLogin\ yes/PermitRootLogin\ no/g' /etc/ssh/sshd_config ;
sed -i 's/#UseDNS\ yes/UseDNS\ no/g' /etc/ssh/sshd_config ;
sed -i -r 's@(ChallengeResponseAuthentication) no@\1 yes@g' /etc/ssh/sshd_config ;

service sshd restart ;

echo 'y' | google-authenticator -t -d -f -Q UTF8 -r 3 -R 30 2>&1 > ~/google_authenticator
# EnD
