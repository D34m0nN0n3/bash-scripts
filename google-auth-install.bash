#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.

# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

PACKAGES=( bash )

set -u          # Detect undefined variable
set -o pipefail # Return return code in pipeline fails

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

# Detecting login user info
[[ -n "${SUDO_USER:-}" ]] && login_user="${SUDO_USER:-}" 2> /dev/null

login_user_home="/home/${login_user}"
login_ssh_authorize_path=${login_ssh_authorize_path:-"${login_user_home}/.ssh/authorized_keys"}

# gal - Google Authenticator Libpam
gal_decompress_dir='/tmp/google-authenticator-libpam'
gal_installation_dir='/opt/googleAuthenticator'

### Compile Google Authenticator
yum remove google-authenticator -y;
yum install git-core qrencode pam-devel make gcc wget autoreconf unzip autoconf automake libtool -y;

git_link=${git_link:-"https://github.com/google/google-authenticator-libpam"}
git clone -q "${git_link}.git" "${gal_decompress_dir}"

[[ -d ${gal_installation_dir} ]] && rm -rf ${gal_installation_dir} && mkdir -pv ${gal_installation_dir}

pushd ${gal_decompress_dir}
./bootstrap.sh ; ./configure  --prefix=/opt/googleAuthenticator ; make -j 3 && make install ;


# Install Google Authenticator
unlink /usr/bin/google-authenticator ;
unlink /lib64/security/pam_google_authenticator.so ;
unlink /lib64/security/pam_google_authenticator.la ;
ln -fs ${gal_installation_dir}/bin/google-authenticator /usr/bin/google-authenticator ;
ln -fs ${gal_installation_dir}/lib/security/pam_google_authenticator.so /lib64/security/pam_google_authenticator.so ;
ln -fs ${gal_installation_dir}/lib/security/pam_google_authenticator.la /lib64/security/pam_google_authenticator.la ;

# Config SSH Daemon
sed -i '/#%PAM/a auth\ \ \ \ \ \ \ required\ \ \ \ \ pam_google_authenticator.so nullok' /etc/pam.d/sshd ;
if [ -f "${login_ssh_authorize_path}" ]; then
   sed -i -r '/auth[[:space:]]+substack[[:space:]]+password-auth/s/^/#/' /etc/pam.d/sshd ;
   echo -e 'AuthenticationMethods publickey,keyboard-interactive' >> /etc/ssh/sshd_config ;
fi

sed -i 's/#PermitRootLogin\ yes/PermitRootLogin\ no/g' /etc/ssh/sshd_config ;
sed -i 's/#UseDNS\ yes/UseDNS\ no/g' /etc/ssh/sshd_config ;
sed -i -r 's@(ChallengeResponseAuthentication) no@\1 yes@g' /etc/ssh/sshd_config ;

sudo -u ${login_user} google-authenticator -t -d -f -Q UTF8 -C -r 3 -R 30 -w 17 -e 10 -s ${login_user_home}/.google_authenticator && systemctl restart sshd.service ;

# EnD
exit
