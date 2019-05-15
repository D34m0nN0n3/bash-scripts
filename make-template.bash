#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Creating a RedHat/CentOS VMware Gold Template.

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

SED='/bin/sed'
LOGD='/var/log/'
LOGF='null'
INTERFACE='null'

# Change password on netx logon
chage -d0 root
chage -d0 adminos

# Un-configure - Networking
# Remove any persistent udev-rules
rm -f /etc/udev/rules.d/70-persistent-net.rules > /dev/null 2>&1

# Remove unique network details from ifcfg scripts
for INTERFACE in {eth*,ens*,env*}
do
sed -i '/UUID\|HWADDR\|IPADDR\|NETWORK\|NETMASK\|GATEWAY\|DNS1\|DNS2\|DNS3\|DOMAIN\|USERCTL/d' /etc/sysconfig/network-scripts/ifcfg-${INTERFACE} > /dev/null 2>&1
sed -i 's,BOOTPROTO\=none,BOOTPROTO\=dhcp,' /etc/sysconfig/network-scripts/ifcfg-${INTERFACE} > /dev/null 2>&1
done
sed -i '1,2!d' /etc/hosts > /dev/null 2>&1

# Un-configure - Registration Details
# Remove any registration details depending on the method previously used
rm /etc/sysconfig/rhn/systemid > /dev/null 2>&1

# Subscription Manager (RHSM) registered guests
subscription-manager unsubscribe --all && subscription-manager unregister && subscription-manager clean > /dev/null 2>&1

# Clean yum cache
yum clean all > /dev/null 2>&1

# Remove any sshd public/private key pairs
rm -rf /etc/ssh/*key* > /dev/null 2>&1

# Remove old kernels
/bin/package-cleanup --oldkernels --count=1 -y > /dev/null 2>&1

# Shrink the log space, remove old logs and truncate logs
logrotate -f /etc/logrotate.conf > /dev/null 2>&1
rm -rfv ${LOGD}anaconda && rm -f ${LOGD}dmesg.old ${LOGD}*-???????? ${LOGD}*.gz > /dev/null 2>&1
for LOGF in {audit/audit.log,grubby,lastlog,wtmp}; do cat /dev/null > ${LOGD}${LOGF}; done

# Sort /etc/passwd and /etc/group
pwck -s ; grpck -s > /dev/null 2>&1

# Remove root users shell history
/bin/rm -f ~root/.bash_history > /dev/null 2>&1
unset HISTFILE

# Configure sys-unconfig
sys-unconfig
touch /.unconfigured

# Poweroff
systemctl halt
#END
