#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# This scripr the client registration on katello servers.

ARGCHECK=$#
IDSERV='null'
IDKEY='null'
IDORG=''
MINARG=2

PACKAGES=( bash )

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

if [[ -z ${IDORG} ]]; then
   IDORG='Default_Organization'
fi

function pad {
  PADDING="..............................................................."
  TITLE=$1
  printf "%s%s  " "${TITLE}" "${PADDING:${#TITLE}}"
}

# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

# initialize PRINT_* counters to zero
fail_count=0 ; success_count=0

function print_FAIL {
  echo -e "$@ \e[1;31mFAIL\e[0;39m\n"
  let fail_count++
  return 0
}

function print_SUCCESS {
  echo -e "$@ \e[1;32mSUCCESS\e[0;39m\n"
  let success_count++
  return 0
}

function print_usage {
cat <<EOF
Registration this client on Katello. 
     Options:
        -s <service>       Specify server name or ip address server repository.
        -k <key>           This activation key may be used during system registration.
        -o <organization>  Specify organization name on Satellite/Katello server. (opcional)
    
     Example: bash katello.bash -s <name> -k <key> -o <organization>
EOF
}

if [ "${ARGCHECK}" -lt "${MINARG}" ] ; then
print_usage
exit 1
fi

if [ "${ARGCHECK}" -gt "4" ]; then
while getopts "s:k:o:" OPTION
do
     case $OPTION in
         s) IDSERV=${OPTARG} ;;
         k) IDKEY=${OPTARG} ;;
         o) IDORG=${OPTARG} ;;
         *) exit 1 ;;
     esac
done
else
while getopts "s:k:" OPTION
do
     case $OPTION in
         s) IDSERV=${OPTARG} ;;
         k) IDKEY=${OPTARG} ;;
         *) exit 1 ;;
     esac
done
fi


function disable_repo {
  pad "Disable default repo"
subscription-manager unregister > /dev/null 2>&1 ;
subscription-manager clean > /dev/null 2>&1 ;
yum-config-manager --disable * > /dev/null 2>&1 ;
yum remove katello-ca-consumer* -y > /dev/null 2>&1 ;
sed -i 's,enabled\=1,enabled\=0,' /etc/yum/pluginconf.d/enabled_repos_upload.conf > /dev/null 2>&1 ;
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Error can't disabled"
    exit 1
  fi
  print_SUCCESS
}

function reg_host {
  pad "The client registration"
yum localinstall http://${IDSERV}/pub/katello-ca-consumer-latest.noarch.rpm -y > /dev/null 2>&1 &&
  if [[ "${IDKEY}" == "" || "${IDKEY}" == *" "* ]]; then
  echo "Error! Invalid key!"
  exit 1
  fi
subscription-manager register --org="${IDORG}" --activationkey="${IDKEY}" --force > /dev/null 2>&1 &&
yum install katello-agent -y > /dev/null 2>&1 &&
rm -f /tmp/katello-ca-consumer-latest.noarch.rpm > /dev/null 2>&1 &&
rm -f /etc/yum.repos.d/temp.repo > /dev/null 2>&1 ;
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo -n "Error can't registration"
    exit 1
  fi
  print_SUCCESS
}

function foreman_user {
  pad "The ceate user and authorized key"
# Satellite webUI >> Hosts >> All Hosts >> Edit the client.example.com >> Parameters tab >>
# Add Parameter >> Specify Name as remote_execution_ssh_user and set its value to [foreman-proxy-user] >>
# click Submit.
# The ceate user for remote execution features Katello
userdel --remove foreman-proxy-user --force > /dev/null 2>&1 ;
useradd --create-home --password $(python -c 'import crypt; print(crypt.crypt("$(base64 -w 16 /dev/urandom | tr -d /+ | head -n 1)"))') --comment "User for remote execution features Katello" --system foreman-proxy-user > /dev/null 2>&1 | logger -p user.error -t `basename "$0"` &&
# The add authorized key for remote execution features Katello
mkdir -p ~foreman-proxy-user/.ssh/ > /dev/null 2>&1 | logger -p user.error -t `basename "$0"` &&
curl --insecure --output ~foreman-proxy-user/.ssh/authorized_keys https://${IDSERV}:9090/ssh/pubkey > /dev/null 2>&1 | logger -p user.error -t `basename "$0"` &&
chown foreman-proxy-user:foreman-proxy-user -R ~foreman-proxy-user/.ssh/ && chmod 600 ~foreman-proxy-user/.ssh/authorized_keys > /dev/null 2>&1 | logger -p user.error -t `basename "$0"` &&
restorecon -Rv ~foreman-proxy-user/.ssh/ > /dev/null 2>&1 &&
# The add permission for remote execution features Katello
cat << 'EOF' > /etc/sudoers.d/foreman-proxy-user
# User for remote execution features Katello
foreman-proxy-user   ALL=NOPASSWD:   ALL
EOF
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo -n "Error can't adding user"
  else
    print_SUCCESS
  fi
}

function puppet_setup {
  pad "Installing and configuring puppet agent"
yum install puppet -y && puppet config set server $IDSERV && puppet agent --test --noop && systemctl enable puppet --now ;
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_WARNING
    echo -n "Puppet can't installed"
  else
    print_SUCCESS
  fi
}

function update_host {
  read -p "Do you want update system? (y/n): " choice
        while :
        do
            case "$choice" in
                y|Y) yum update -y; break;;
                n|N) echo "Don't forget to upgrade later!"; break;;
                * ) read -p "Please enter 'y' or 'n': " choice;;
            esac
        done
}

function reboot_host {
  read -p "Do you want reboot system? (y/n): " choice
        while :
        do
            case "$choice" in
                y|Y) systemctl reboot; break;;
                n|N) echo "Don't forget to reboot later!"; break;;
                * ) read -p "Please enter 'y' or 'n': " choice;;
            esac
        done
}

disable_repo ; reg_host && puppet_setup ; foreman_user ; update_host && reboot_host
#END
exit
