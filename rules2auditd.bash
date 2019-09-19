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

auditctl -l && cat /dev/null > /etc/audit/rules.d/audit.rules && augenrules

cat <<-EOF>> /etc/audit/audit.rules
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
EOF

service auditd stop && service auditd start
systemctl status auditd.service && auditctl -s && auditctl -l

# END
