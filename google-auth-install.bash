#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Installing Google Authenticator on Amazon Linux and RHEL\CentOS.
# Thank you for helping NikSonn (https://github.com/NikSonn).

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

# initialize PRINT_* counters to zero
fail_count=0 ; warning_count=0 ; success_count=0

function pad {
  PADDING="..............................................................."
  TITLE=$1
  printf "%s%s  " "${TITLE}" "${PADDING:${#TITLE}}"
}

function print_FAIL {
  echo -e "$@ \e[1;31mFAIL\e[0;39m\n"
  let fail_count++
  return 0
}

function print_WARNING {
  echo -e "$@ \e[1;33mPASS\e[0;39m\n"
  let warning_count++
  return 0
}

function print_SUCCESS {
  echo -e "$@ \e[1;32mSUCCESS\e[0;39m\n"
  let success_count++
  return 0
}

function panic {
  local error_code=${1} ; shift
  echo "Error: ${@}" 1>&2
  exit ${error_code}
}

# Detecting login user info
[[ -n "${USER:-}" && -z "${SUDO_USER:-}" ]] && login_user="$USER" || login_user="$SUDO_USER" 2> /dev/null
[[ "${login_user}" == 'root' ]] && login_user_home='/root' || login_user_home="/home/${login_user}"
login_ssh_authorize_path=${login_ssh_authorize_path:-"${login_user_home}/.ssh/authorized_keys"}

# Install Google Authenticator Libpam
function install_gal_git {
pad "Install Google Authenticator Libpam:"
# gal - Google Authenticator Libpam
gal_decompress_dir='/tmp/google-authenticator-libpam'
gal_installation_dir='/opt/googleAuthenticator'

### Compile Google Authenticator
yum remove google-authenticator -y > /dev/null 2>&1 ;
yum install git-core qrencode pam-devel make gcc wget autoreconf unzip autoconf automake libtool -y > /dev/null 2>&1 ;

git_link=${git_link:-"https://github.com/google/google-authenticator-libpam"}
git clone -q "${git_link}.git" "${gal_decompress_dir}" > /dev/null 2>&1

[[ -d ${gal_installation_dir} ]] && rm -rf ${gal_installation_dir} && mkdir -pv ${gal_installation_dir}

(pushd ${gal_decompress_dir} && ./bootstrap.sh ; ./configure  --prefix=/opt/googleAuthenticator ; make -j 3 && make install) > /dev/null 2>&1 ;

# Setup Google Authenticator
unlink /usr/bin/google-authenticator > /dev/null 2>&1 ;
unlink /lib64/security/pam_google_authenticator.so > /dev/null 2>&1 ;
unlink /lib64/security/pam_google_authenticator.la > /dev/null 2>&1 ;
ln -fs ${gal_installation_dir}/bin/google-authenticator /usr/bin/google-authenticator > /dev/null 2>&1 ;
ln -fs ${gal_installation_dir}/lib/security/pam_google_authenticator.so /lib64/security/pam_google_authenticator.so > /dev/null 2>&1 ;
ln -fs ${gal_installation_dir}/lib/security/pam_google_authenticator.la /lib64/security/pam_google_authenticator.la > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

# Install Google Authenticator Libpam
function install_gal_repo {
pad "Install Google Authenticator Libpam:"
yum install google-authenticator -y > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_FAIL
    echo -n "Connect EPEL repository for google-authenticator installation" && exit 1
else
    print_SUCCESS
fi
}

# Config SSH Daemon
function config_sshd {
pad "Configuring SSH Daemon:"
sed -i -e "$(grep -n '^auth[[:space:]]' /etc/pam.d/sshd | tail -1 | cut -f1 -d':')a auth\ \ \ \ \ \ \ required\ \ \ \ \ pam_google_authenticator.so nullok" /etc/pam.d/sshd ;
sed -i 's/PermitRootLogin\ yes/PermitRootLogin\ no/g' /etc/ssh/sshd_config ;
sed -i 's/#UseDNS\ yes/UseDNS\ no/g' /etc/ssh/sshd_config ;
sed -i -r 's@(ChallengeResponseAuthentication) no@\1 yes@g' /etc/ssh/sshd_config ;
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

# Config SSH Daemon Authentication Methods
function config_sshd_authmethods {
if [ -f "${login_ssh_authorize_path}" ]; then
   sed -i -r '/auth[[:space:]]+substack[[:space:]]+password-auth/s/^/#/' /etc/pam.d/sshd ;
   echo -e 'AuthenticationMethods publickey,keyboard-interactive' >> /etc/ssh/sshd_config ;
fi
}

# Config Google Authenticator
function config_gal_git {
echo "Configuring Google Authenticator:"
sudo -u ${login_user} google-authenticator -t -d -f -Q UTF8 -C -r 3 -R 30 -w 17 -e 10 -s ${login_user_home}/.google_authenticator && systemctl restart sshd.service ;
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

# Config Google Authenticator
function config_gal_repo {
echo "Configuring Google Authenticator:"
sudo -u ${login_user} google-authenticator -t -d -f -Q UTF8 -r 3 -R 30 -w 17 -e 10 -s ${login_user_home}/.google_authenticator && systemctl restart sshd.service ;
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

OS=`cat /etc/os-release | grep ^NAME | cut -f2 -d\"`
if [[ "$OS" == "Amazon Linux" ]]; then
  install_gal_git && config_sshd && config_sshd_authmethods && config_gal_git
elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Red Hat Enterprise Linux Server" ]]; then
  install_gal_repo && config_sshd && config_gal_repo
fi

# EnD
exit
