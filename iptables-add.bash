#!/usr/bin/env bash
#
# For installing iptables firewall!
# 
# <blink>
   ###################### IMPORTANT ########################
   ###### DO NOT MAKE ANY CHANGES TO THIS FILE. IT IS ######
   ######        MAINTAINED BY Prigoda Dmitriy.       ######
   #########################################################
# </blink>

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

PACKAGES=( bash )
ssh=${ssh-ssh -o StrictHostKeyChecking=no}
scp=${scp-scp -o StrictHostKeyChecking=no -q}

function panic {
  local error_code=${1} ; shift
  echo "Error: ${@}" 1>&2
  exit ${error_code}
}

# initialize PRINT_* counters to zero
pass_count=0 ; fail_count=0 ;exist_count=0 ; success_count=0

SUDO='/usr/bin/sudo'

# Export LANG so we get consistent results
# For instance, en_US uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

function pad {
  PADDING="..............................................................."
  TITLE=$1
  printf "%s%s  " "${TITLE}" "${PADDING:${#TITLE}}"
}

function print_EXIST {
  echo -e "$@ \e[1;31mEXIST\e[0;39m\n"
  let exist_count++
  return 0
}

function print_FAIL {
  echo -e "$@ \e[1;31mFAIL\e[0;39m\n"
  let exist_count++
  return 0
}

function print_SUCCESS {
  echo -e "$@ \e[1;32mSUCCESS\e[0;39m\n"
  let success_count++
  return 0
}

function print_PASS {
  echo -e "$@ \e[1;33mPASS\e[0;39m\n"
  let pass_count++
  return 0
}

function install_packages {
  pad "Installing iptables firewall"
  yum install iptables-services iptables-utils -y > /dev/null 2>&1
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Error installing needed packages"
    exit 132
  fi
  print_SUCCESS
}

function disable_firewalld {
  pad "Disable firewalld"
  for STOPACTION in {stop,disable,mask}
  do
  systemctl ${STOPACTION} firewalld > /dev/null 2>&1
  done
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Can't disable firewalld"
    exit 1
  fi
  print_SUCCESS
}

function enable_iptables {
pad "Enable iptables"
  for STARTACTION in {enable,start,status}
  do
  systemctl ${STARTACTION} iptables > /dev/null 2>&1
  done
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Can't disable firewalld"
    exit 1
  fi
  print_SUCCESS
}

function create_scriptcfg {
pad "Creating script and config rules files for iptables"
  
IPTABLES_CONFIG=/usr/sbin/iptcfg
IPTABLES_CUSTEM=/etc/sysconfig/custom

# Create scripts configuration
# Main script whit default rules
if [ ! -f $IPTABLES_CONFIG ]; then
cat << EOF > $IPTABLES_CONFIG
#!/usr/bin/env bash
#
# Windows file conver dos2unix.
#
PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH
export PATH
#
# ENABLED NAT FORWARD
# echo 1 > /proc/sys/net/ipv4/ip_forward
#
IPT=iptables
IPTS=iptables-save
IPTR=iptables-restore
FILE='/etc/sysconfig/custom'

# +++ Start and load rules from file /etc/sysconfig/iptables +++
start() {
        echo -n "Starting firewall..."
        $IPTR -c /etc/sysconfig/iptables
        echo "Done"
}

# +++ Stop and save rules in files /etc/sysconfig/iptables +++
stop() {
        echo -n "Stop firewall..."
        $IPTS -c > /etc/sysconfig/iptables
        echo "Done"
}

panic_mode() {
$IPT -F
$IPT -t nat -F
$IPT -t mangle -F
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT DROP
}

# +++ Enable panic mode. Set all policy - DROP rules. +++
panic() {
  read -p "Do you want to enable panic mode? (y/n) " choice
        while :
        do
            case "$choice" in
                y|Y) panic_mode; break;;
                n|N) echo "No panic, operation canceled..."; exit 1;;
                * ) read -p "Please enter 'y' or 'n': " choice;;
            esac
        done
}

# +++ Load default rules +++
reset() {
$IPT -F
$IPT -t nat -F
$IPT -t mangle -F
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT ACCEPT
# === STATE RULES ===
$IPT -A INPUT -m state --state INVALID -j DROP
$IPT -A FORWARD -m state --state INVALID -j DROP
$IPT -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
# === LOCALHOST ===
$IPT -A FORWARD ! -i lo -s 127.0.0.1 -j DROP
$IPT -A INPUT ! -i lo -s 127.0.0.1 -j DROP
$IPT -A FORWARD ! -i lo -d 127.0.0.1 -j DROP
$IPT -A INPUT ! -i lo -d 127.0.0.1 -j DROP
$IPT -A INPUT -s 127.0.0.1 -j ACCEPT
$IPT -A OUTPUT -d 127.0.0.1 -j ACCEPT
# === ICMP ENABLED ===
$IPT -A INPUT -p icmp -m limit --limit 1/s --limit-burst 1 -j ACCEPT
$IPT -A INPUT -p icmp -m limit --limit 1/s --limit-burst 100 -j LOG --log-prefix "ICMP FLOOD: " --log-level info
$IPT -A INPUT -p icmp -j DROP
$IPT -A OUTPUT -p icmp -j ACCEPT
# === SSH ENABLED ===
$IPT -A INPUT -p tcp -m state --state NEW --dport 22 -m recent --name ssh --update --seconds 25 -j DROP
$IPT -A INPUT -p tcp -m state --state NEW --dport 22 -s 10.0.0.0/8 -m recent --name ssh --set -j ACCEPT
# === LOG ENABLED ===
$IPT -A INPUT -p tcp -m state --state NEW --dport 22 -j LOG --log-prefix "SSH-WARNING: " --log-level warning
# === STOP SCAN ===
$IPT -A INPUT -p tcp --tcp-flags ALL FIN -m limit --limit 1/m --limit-burst 1  -j LOG --log-prefix "FIN-SCAN: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL SYN,FIN -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "SYNFIN-SCAN: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL SYN,FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL URG,PSH,FIN -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "NMAP-XMAS-SCAN: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL URG,PSH,FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ACK,FIN FIN -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "FIN scan: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ACK,FIN FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ACK,PSH PSH -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "PSH scan: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
$IPT -A INPUT -p tcp --tcp-flags ACK,URG URG -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "URG scan: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL ALL -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "XMAS scan: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL NONE -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "NULL scan: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL URG,PSH,SYN,FIN -m limit --limit 1/m --limit-burst 1 -j LOG --log-prefix "NMAP-ID: " --log-level info
$IPT -A INPUT -p tcp --tcp-flags ALL URG,PSH,SYN,FIN -j DROP
# === RATE LIMITING ===
$IPT -A INPUT -p tcp --syn -m limit --limit 180/s --limit-burst 10000 -j ACCEPT
$IPT -A INPUT -p tcp --syn -j DROP
$IPT -A INPUT -p udp -m state --state NEW -m limit --limit 24/s --limit-burst 10000 -j ACCEPT
$IPT -A INPUT -p udp -m state --state NEW -j DROP
}

# +++ Custom rules +++
init() {
        echo -n "init firewall..."
        reset

# RULES FIREWALL
#
. /etc/sysconfig/custom
#
# SAVE RULES IN FILE
$IPTS -c > /etc/sysconfig/iptables
echo "Done"
}

edit() {
  echo "Editing $FILE..."
  vim -c ":set tabstop=8" -c ":set shiftwidth=8" -c ":set noexpandtab" $FILE
  echo -e "\t\t[OK]"
}

# +++ Show rules iptables +++
show() {
        echo -n "Show firewall..."
        $IPT -L -n -v
        exit 0
}

PS3='Select action: '
options=("Start and load rules from file /etc/sysconfig/iptables" "Stop and save rules from file /etc/sysconfig/iptables" "Restart and load custom rules" "Restart and load default rules" "Edit custom rules" "Enable panic mode" "Show rules iptables" "Quit")
        select opt in "${options[@]}"
        do
        case $opt in
                "Start and load rules from file /etc/sysconfig/iptables") start;;
                "Stop and save rules from file /etc/sysconfig/iptables") stop;;
                "Restart and load custom rules") init;;
                "Restart and load default rules") reset;;
                "Edit custom rules") edit;;
                "Enable panic mode") panic;;
                "Show rules iptables") show;;
                "Quit") break;;
                *) echo "Invalid option. Try another one.";continue;;
        esac
        done

exit 0
EOF

chown root:root $IPTABLES_CONFIG && chmod 750 $IPTABLES_CONFIG

if [ ! -x $IPTABLES_CONFIG ]; then
print_FAIL
echo -n $"$IPTABLES_CONFIG does not exec."; warning; echo
return 1
fi
print_PASS
return 0
  
# Custom rules
cat << EOF > $IPTABLES_CUSTEM
# === DNS SERVER ===
$IPT -A PREROUTING -t raw -j NOTRACK -m udp -p udp --dport 53
$IPT -A PREROUTING -t raw -j NOTRACK -m tcp -p tcp --dport 53
$IPT -A INPUT -p udp --dport 53 -j ACCEPT
$IPT -A INPUT -p tcp --dport 53 -j ACCEPT
# === FTP SERVER ===
modprobe ip_conntrack_ftp
$IPT -A INPUT -p tcp -m multiport --dports 20,21 -j ACCEPT
# === WEB CONTROL ===
$IPT -A INPUT -p tcp --dport 3389 -s 10.0.0.0/8 -j ACCEPT
$IPT -A INPUT -p tcp --dport 9090 -s 10.0.0.0/8 -j ACCEPT
$IPT -A INPUT -p tcp --dport 10000 -s 10.0.0.0/8 -j ACCEPT
# === KATELLO AGENT ===
$IPT -A INPUT -p udp -m multiport --dports 67,69 -j ACCEPT
$IPT -A INPUT -p tcp -m multiport --dports 5000,5647,8000,8140,8443,9090 -j ACCEPT
# === ITM AGENT ===
$IPT -A INPUT -p udp --dport 1918 -j ACCEPT
$IPT -A INPUT -p tcp -m multiport --dports 1918,1919,1920,3660,6014,10110,14206,15001 -j ACCEPT
# === NETBACKUP AGENT ===
$IPT -A INPUT -p tcp -m multiport --dports 443,1556,2821,10082,10102,13720,13724,13782 -j ACCEPT
# === Cocpit ===
$IPT -A INPUT -p tcp -m multiport --dport 9090 -j ACCEPT
# === END ===
EOF

chown root:root $IPTABLES_CUSTEM && chmod 640 $IPTABLES_CUSTEM

if [ ! -x $IPTABLES_CUSTEM ]; then
print_EXIST
return 1
fi
print_PASS
return 0
else
print_EXIST
return 1
fi
print_SUCCESS
}

install_packages && disable_firewalld && enable_iptables && create_scriptcfg

# vim: ai sw=2
#END
exit 0
