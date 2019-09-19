#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Adding rules for auditd.
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

function backup_rules {
pad "Backup rules files:"
cp -a /etc/audit/audit.rules.prev /root/audit.rules.prev.back && cat /dev/null > /etc/audit/audit.rules.prev ;
cp -a /etc/audit/rules.d/audit.rules /root/audit.rules.back && cat /dev/null > /etc/audit/rules.d/audit.rules ;
if [ $? -ne 0 ]; then
    print_FAIL
else
    print_SUCCESS
fi
}

function add_rules {
pad "Add new rules to files:"
cat <<-'EOF'>> /etc/audit/rules.d/audit.rules
## First rule - delete all
-D

## Increase the buffers to survive stress events.
## Make this bigger for busy systems
-b 8192

## Set failure mode to syslog
-f 1

## Audit kernel modules
-w /sbin/modprobe -p x -k auditkernel

## Audit system configuration files
-w /etc/sysconfig/ -p rwa -k auditconf

## Audit network connections (IPv4, IPv6)
-a exit,always -F arch=b32 -S socket -F auid>=500 -F auid!=4294967295 -F a0=2 -F success=1 -k auditconn
-a exit,always -F arch=b64 -S socket -F auid>=500 -F auid!=4294967295 -F a0=2 -F success=1 -k auditconn
-a exit,always -F arch=b32 -S socket -F auid>=500 -F auid!=4294967295 -F a0=10 -F success=1 -k auditconn
-a exit,always -F arch=b64 -S socket -F auid>=500 -F auid!=4294967295 -F a0=10 -F success=1 -k auditconn

## Audit create file as root
-a exit,always -F arch=b32 -F uid=0 -S creat -k audit-rootfile
-a exit,always -F arch=b64 -F uid=0 -S creat -k audit-rootfile

## Audit open file as users account 
-a exit,always -F arch=b32 -F auid>=1000 -S open -k audit-userfile
-a exit,always -F arch=b64 -F auid>=1000 -S open -k audit-userfile

## Unauthorized Access (unsuccessful) 
-a exit,always -F arch=b32 -S creat -S open -S openat -S open_by_handle_at -S truncate -S ftruncate -F exit=-EACCES -F auid>=500 -F auid!=4294967295 -k auditfaccess
-a exit,always -F arch=b32 -S creat -S open -S openat -S open_by_handle_at -S truncate -S ftruncate -F exit=-EPERM -F auid>=500 -F auid!=4294967295 -k auditfaccess
-a exit,always -F arch=b64 -S creat -S open -S openat -S open_by_handle_at -S truncate -S ftruncate -F exit=-EACCES -F auid>=500 -F auid!=4294967295 -k auditfaccess
-a exit,always -F arch=b64 -S creat -S open -S openat -S open_by_handle_at -S truncate -S ftruncate -F exit=-EPERM -F auid>=500 -F auid!=4294967295 -k auditfaccess

## Access to docker 
-w /usr/bin/docker -p rwxa -k auditdocker

## Sudoers file changes 
-w /etc/sudoers -p wa -k sudo_modification

## Passwd  modificatons
-w /usr/bin/passwd -p x -k passwd_modification

## Tools to edit group and users
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupmod -p x -k group_modification
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/adduser -p x -k user_modification

## Changes to network files
-w /etc/hosts -p wa -k network_modifications
-w /etc/sysconfig/network -p wa -k network_modifications
-w /etc/networks/ -p wa -k network 
-a exit,always -F dir=/etc/NetworkManager/ -F perm=wa -k network_modifications

## Audit executive command 
-a exit,always -F arch=b32 -S execve -k auditcmd
-a exit,always -F arch=b64 -S execve -k auditcmd

## BLOCK RULE EDITING 
-e 2  
EOF > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

function kexec_target {
pad "Create kexec target:"
# Reload kernel fast.
SERVICE_NAME="kexec-load"
#INSTANCABLE="@"
SYSTEMD_PREFIX="systemd/system"
SYSTEMD_SERVICE="/etc/$SYSTEMD_PREFIX/${SERVICE_NAME}${INSTANCABLE}.service"

cat > $SERVICE_NAME << EOF
[Unit]
Description=load \$(uname -r) kernel into the current kernel
Documentation=https://wiki.archlinux.org/index.php/Kexec
DefaultDependencies=no
Before=shutdown.target umount.target final.target kexec.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c '/sbin/kexec -l /boot/vmlinuz-\$(/bin/uname -r) --initrd=/boot/initramfs-\$(/bin/uname -r).img --reuse-cmdline'
[Install]
WantedBy=kexec.target
EOF

cp -f $SERVICE_NAME $SYSTEMD_SERVICE
chown root:root $SYSTEMD_SERVICE
restorecon $SYSTEMD_SERVICE
systemctl daemon-reload
systemctl enable $SERVICE_NAME
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

backup_rules && add_rules && augenrules 
service auditd stop > /dev/null 2>&1 && service auditd start > /dev/null 2>&1

systemctl status auditd.service > /root/rules2auditd.log
auditctl -s >> /root/rules2auditd.log
auditctl -l >> /root/rules2auditd.log

sleep 5
systemctl start kexec.target
# END
exit 0
