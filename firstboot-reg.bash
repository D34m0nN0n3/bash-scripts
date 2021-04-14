#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.

PACKAGES=( bash )

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

function print_usage {
cat <<EOF
Creat service registration this client on Katello.
     Options:
        -s <service>       Specify server name or ip address server repository.
        -k <key>           This activation key may be used during system registration.
        -o <organization>  Specify organization name on Satellite/Katello server.
        -p <puppet env>    Puppet main environment. (opcional)
    
     Example: bash firstboot-reg.bash -s <name> -k <key> -o <organization>
EOF
}

ARGCHECK=$#
RHS_SRV='null'
RHS_ORG='null'
RHS_AK='null'
PUPPET_MAIN_ENV=''
MINARG=3

if [ "${ARGCHECK}" -lt "${MINARG}" ] ; then
print_usage
exit 1
fi

if [[ -z ${PUPPET_MAIN_ENV} ]]; then
   PUPPET_MAIN_ENV='KT_GVC_Library_GVC_Puppet_Default_26'
fi

if [ "${ARGCHECK}" -gt "5" ]; then
while getopts "s:k:o:p:" OPTION
do
     case $OPTION in
         s) RHS_SRV=${OPTARG} ;;
         k) RHS_AK=${OPTARG} ;;
         o) RHS_ORG=${OPTARG} ;;
         p) PUPPET_MAIN_ENV=${OPTARG} ;;
         *) exit 1 ;;
     esac
done
else
while getopts "s:k:o:" OPTION
do
     case $OPTION in
         s) RHS_SRV=${OPTARG} ;;
         k) RHS_AK=${OPTARG} ;;
         o) RHS_ORG=${OPTARG} ;;
         *) exit 1 ;;
     esac
done
fi

cat << 'EOF' > /usr/bin/check-network-boot-exist
#!/usr/bin/env bash
# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

# Define some default values for this script
. /etc/first-boot-reg.env
CHECH_RHS_RESPONSE=$(curl -LI https://${RHS_SRV} -o /dev/null -w '%{http_code}\n' -s)

# Main script
if [[ $CHECH_RHS_RESPONSE != 000 ]]; then
  /usr/bin/touch /.firstboot-reg && echo '# See default values in file: /etc/first-boot-reg.env' > /.firstboot-reg
else
  echo "No server connect" && exit 0
fi

# END
exit 0
EOF

cat << 'EOFF' > /usr/bin/first-boot-reg
#!/usr/bin/env bash
# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

# initialize PRINT_* counters to zero
fail_count=0 ; success_count=0

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
  echo -e "$@ \e[1;33mWARNING\e[0;39m\n"
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

# Define some default values for this script
. /etc/first-boot-reg.env

# Main script
function disable_repo {
subscription-manager unregister > /dev/null 2>&1 ;
subscription-manager clean > /dev/null 2>&1 ;
yum-config-manager --disable * > /dev/null 2>&1 ;
yum remove katello-ca-consumer* -y > /dev/null 2>&1 ;
sed -i 's,enabled\=1,enabled\=0,' /etc/yum/pluginconf.d/enabled_repos_upload.conf > /dev/null 2>&1 ;
}

function rhs_reg {
find /etc/yum.repos.d/ -type f -exec sed -i 's/enabled\ \=\ 1/enabled\ \= 0/' {} \; > /dev/null 2>&1 ;
yum localinstall http://${RHS_SRV}/pub/katello-ca-consumer-latest.noarch.rpm -y > /dev/null 2>&1 &&
subscription-manager register --org="${RHS_ORG}" --activationkey="${RHS_AK}" --force > /dev/null 2>&1 &&
yum install katello-agent -y > /dev/null 2>&1
}

function puppet_reg {
yum install puppet-agent -y > /dev/null 2>&1 && puppet config set server ${RHS_SRV} > /dev/null 2>&1 && puppet config set --section main environment ${PUPPET_MAIN_ENV} > /dev/null 2>&1 && puppet agent --test --noop > /dev/null 2>&1
}

function add_foreman-proxy-user {
userdel --remove foreman-proxy-user --force 2>&1 ;
useradd --create-home --password $(python -c 'import crypt; print(crypt.crypt("$(base64 -w 16 /dev/urandom | tr -d /+ | head -n 1)"))') --comment "User for remote execution features Katello" --system foreman-proxy-user > /dev/null 2>&1 &&
mkdir -p ~foreman-proxy-user/.ssh/ > /dev/null 2>&1 &&
curl --insecure --output ~foreman-proxy-user/.ssh/authorized_keys https://${RHS_SRV}:9090/ssh/pubkey > /dev/null 2>&1 &&
chown foreman-proxy-user:foreman-proxy-user -R ~foreman-proxy-user/.ssh/ && chmod 600 ~foreman-proxy-user/.ssh/authorized_keys > /dev/null 2>&1 &&
restorecon -Rv ~foreman-proxy-user/.ssh/ > /dev/null 2>&1 ;
}

function add_sudoers {
cat <<- 'EOF' > /etc/sudoers.d/foreman-proxy-user
# User for remote execution features Katello
foreman-proxy-user   ALL=NOPASSWD:   ALL
EOF
}

if [ ! -f /.firstboot-reg ]; then
  echo "Check connect fail" && exit 0
else
  systemctl disable systemd-firstboot-reg
fi

pad "Disable default repo:"
disable_repo
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

pad "Registration on RHS:"
rhs_reg
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

pad "Puppet agent. Installation and registration"
puppet_reg
if [ $? -ne 0 ]; then 
    print_WARNING
    echo "Puppet not installed or not configured.
else
    print_SUCCESS
fi

pad "Create user account for remote exec:"
add_foreman-proxy-user
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

pad "Create sudoers rules:"
add_sudoers
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

systemctl disable systemd-firstboot-reg > /dev/null 2>&1
# END
exit 0
EOFF

for SCRIPT in {check-network-boot-exist,first-boot-reg}; do chmod +x /usr/bin/${SCRIPT}; done

cat <<- EOF > /etc/first-boot-reg.env
RHS_SRV=${RHS_SRV}
RHS_ORG=${RHS_ORG}
RHS_AK=${RHS_AK}
PUPPET_MAIN_ENV=${PUPPET_MAIN_ENV}
EOF

cat <<- 'EOF' > /etc/systemd/system/systemd-firstboot-reg.service
[Unit]
Description=First Boot registration on RHS
Documentation=man:systemd-firstboot(1)
DefaultDependencies=no
Conflicts=shutdown.target
After=network-online.target systemd-readahead-collect.service systemd-readahead-replay.service systemd-remount-fs.service
ConditionPathExists=!/.firstboot-reg

[Service]
Type=oneshot
TimeoutSec=0
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal
SyslogLevel=err
ExecStartPre=/usr/bin/check-network-boot-exist
ExecStart=/usr/bin/first-boot-reg

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable systemd-firstboot-reg.service
# END
exit 0
