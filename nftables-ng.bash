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

function install_packages {
  pad "Installing Netfilter's NFTable firewall"
which nft >&/dev/null
if [ "$?" != 0 ]; then
    echo -n "Not Found Netfilter's NFTable firewall. Install now."
    dnf install -y nftables > /dev/null 2>&1
    echo -e "\n[\e[1;32mDONE\e[0;39m]\n"
fi
  RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Error installing needed packages"
    exit 132
  fi
  print_SUCCESS
}

function kernel_settings {
  pad "Change kernel settings"
cat <<-'EOF' > /etc/sysctl.d/99-sysctl.conf
kernel.printk = 4 4 1 7 
kernel.panic = 10 
kernel.sysrq = 0 
kernel.shmmax = 4294967296 
kernel.shmall = 4194304 
kernel.core_uses_pid = 1 
kernel.msgmnb = 65536 
kernel.msgmax = 65536 
vm.swappiness = 20 
vm.dirty_ratio = 80 
vm.dirty_background_ratio = 5 
fs.file-max = 2097152 
net.core.netdev_max_backlog = 262144 
net.core.rmem_default = 31457280 
net.core.rmem_max = 67108864 
net.core.wmem_default = 31457280 
net.core.wmem_max = 67108864 
net.core.somaxconn = 65535 
net.core.optmem_max = 25165824 
net.ipv4.neigh.default.gc_thresh1 = 4096 
net.ipv4.neigh.default.gc_thresh2 = 8192 
net.ipv4.neigh.default.gc_thresh3 = 16384 
net.ipv4.neigh.default.gc_interval = 5 
net.ipv4.neigh.default.gc_stale_time = 120 
net.netfilter.nf_conntrack_max = 10000000 
net.netfilter.nf_conntrack_tcp_loose = 0 
net.netfilter.nf_conntrack_tcp_timeout_established = 1800 
net.netfilter.nf_conntrack_tcp_timeout_close = 10 
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 10 
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 20 
net.netfilter.nf_conntrack_tcp_timeout_last_ack = 20 
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 20 
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 20 
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 10 
net.ipv4.tcp_slow_start_after_idle = 0 
net.ipv4.ip_local_port_range = 1024 65000 
net.ipv4.ip_no_pmtu_disc = 1 
net.ipv4.route.flush = 1 
net.ipv4.route.max_size = 8048576 
net.ipv4.icmp_echo_ignore_broadcasts = 1 
net.ipv4.icmp_ignore_bogus_error_responses = 1 
net.ipv4.tcp_congestion_control = htcp 
net.ipv4.tcp_mem = 65536 131072 262144 
net.ipv4.udp_mem = 65536 131072 262144 
net.ipv4.tcp_rmem = 4096 87380 33554432 
net.ipv4.udp_rmem_min = 16384 
net.ipv4.tcp_wmem = 4096 87380 33554432 
net.ipv4.udp_wmem_min = 16384 
net.ipv4.tcp_max_tw_buckets = 1440000 
net.ipv4.tcp_tw_recycle = 0 
net.ipv4.tcp_tw_reuse = 1 
net.ipv4.tcp_max_orphans = 400000 
net.ipv4.tcp_window_scaling = 1 
net.ipv4.tcp_rfc1337 = 1 
net.ipv4.tcp_syncookies = 1 
net.ipv4.tcp_synack_retries = 1 
net.ipv4.tcp_syn_retries = 2 
net.ipv4.tcp_max_syn_backlog = 16384 
net.ipv4.tcp_timestamps = 1 
net.ipv4.tcp_sack = 1 
net.ipv4.tcp_fack = 1 
net.ipv4.tcp_ecn = 2 
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fin_timeout = 10 
net.ipv4.tcp_keepalive_time = 600 
net.ipv4.tcp_keepalive_intvl = 60 
net.ipv4.tcp_keepalive_probes = 10 
net.ipv4.tcp_no_metrics_save = 1 
net.ipv4.ip_forward = 0 
net.ipv4.conf.all.accept_redirects = 0 
net.ipv4.conf.all.send_redirects = 0 
net.ipv4.conf.all.accept_source_route = 0 
net.ipv4.conf.all.rp_filter = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p > /dev/null 2>&1
RESULT=$?
  if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    echo "Can't change kernel settings"
    exit 1
  fi
  print_SUCCESS
}

function create_scriptcfg {
  pad "Creating script and config rules files for Netfilter's NFTable"
cat /etc/nftables/custome-ruleset.nft
#!/usr/sbin/nft -f
# Copyright (C) 2020 Dmitriy Prigoda <deamon.none@gmail.com>
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
#
# Netfilter's NFTable firewall
# Show custom rules accept: $nft list set inet filter custom_accept
# Add other service accept: $nft add element inet filter custom_accept { port or service }
#
# Anti-DDoS Rules Suck
# Mitigate TCP SYN-flood attacks using nftables: http://ffmancera.net/post/mitigate-tcp-syn-flood-attacks-with-nftables/
#
# more examples are located in files/examples in nftables source.
# For up-to-date information please visit https://wiki.nftables.org
#
# This script is mean to be loaded with `nft -f <file>`
# Save rule sets: $nft list ruleset > /etc/nftables/custome-ruleset.nft
#
# More documentations: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/getting-started-with-nftables_configuring-and-managing-networking

# Flush the rule set
flush ruleset

# Create a table RAW (This table’s purpose is mainly to exclude certain packets from connection tracking using the NOTRACK target.)
table ip raw {
        chain prerouting {
                type filter hook prerouting priority -300; policy accept;
                udp dport { domain, bootps, tftp, ntp, nfs} notrack
                tcp dport { domain, bootps, tftp, ntp, nfs} notrack

        }

}

# Create a table MANGLE (The mangle table is used to modify or mark packets and their header information.)
table ip mangle {
        chain prerouting {
                type filter hook prerouting priority -150; policy accept;
                iifname != "lo" ip saddr 127.0.0.0/8 counter drop comment "These rules assume that your loopback interface"
                ip saddr { 0.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.0.2.0/24,192.168.0.0/16,224.0.0.0/3,240.0.0.0/5} counter drop comment "Block Packets From Private Subnets (Spoofing)"

                ip frag-off & 0x1fff != 0 counter drop
                tcp flags & (fin|syn|rst|ack) != syn ct state new counter drop
                
                tcp flags & (fin|syn|rst|psh|ack|urg) == fin limit rate 1/minute burst 1 packets counter log prefix "FIN-SCAN: " level warn drop
                tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn) limit rate 1/minute burst 1 packets counter log prefix "SYNFIN-SCAN: " level warn drop
                tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|psh|urg) limit rate 1/minute burst 1 packets counter log prefix "NMAP-XMAS-SCAN: " level warn drop
                tcp flags & (fin|ack) == fin limit rate 1/minute burst 1 packets counter log prefix "FIN scan: " level warn drop
                tcp flags & (psh|ack) == psh limit rate 1/minute burst 1 packets counter log prefix "PSH scan: " level warn drop
                tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|rst|psh|ack|urg) limit rate 1/minute burst 1 packets counter log prefix "XMAS scan: " level warn drop
                tcp flags & (fin|syn|rst|psh|ack|urg) == 0x0 limit rate 1/minute burst 1 packets counter log prefix "NULL scan: " level warn drop
                tcp flags & (fin|syn|rst|psh|ack|urg) == (fin|syn|psh|urg) limit rate 1/minute burst 1 packets counter log prefix "NMAP-ID: " level warn drop

                ip protocol icmp limit rate 1/second burst 1 packets counter accept
                ip protocol icmp limit rate 1/second burst 100 packets counter log prefix "ICMP FLOOD: " level warn drop

                ct state new tcp option maxseg size != 536-65535 counter drop comment "Block Uncommon MSS Values. SACK Panic: CVE-2019-11477, CVE-2019-11478, CVE-2019-11479"

        }

}

# Create a table NAT (This table is used for Network Address Translation (NAT). If a packet creates a new connection, the nat table gets checked for rules.)
table ip nat {
        chain prerouting {
                type nat hook prerouting priority -100; policy accept;
        }

        chain postrouting {
                type nat hook postrouting priority -100; policy accept;
        }

}

# Create a table FILTER (The filter table is the default and most commonly used table that rules.)
table inet filter {
        set blackhole {
                type ipv4_addr
                flags timeout
                timeout 1d
        }

        set custom_accept {
                type inet_service
                flags interval
                elements = { 80, 443}
        }

        chain prerouting {
                type filter hook prerouting priority 0; policy accept;
                ip saddr @blackhole drop
        }
        
        chain input {
                type filter hook input priority 0; policy drop;
                iifname != "lo" ip saddr 127.0.0.1 counter drop
                iifname != "lo" ip daddr 127.0.0.1 counter drop
                iifname lo accept comment "Accept any localhost traffic"
                ct state invalid counter drop comment "Drop invalid connections"
                ct state related,established counter accept comment "Accept traffic connections"

                ip protocol icmp icmp type { destination-unreachable, router-solicitation, router-advertisement, time-exceeded, parameter-problem } accept comment "Accept ICMP"
                ip protocol igmp accept comment "Accept IGMP"

                meta l4proto { tcp, udp } @th,16,16 53 counter accept comment "Accept DNS service"
                meta l4proto { tcp, udp } @th,16,16 69 counter accept comment "Accept TFTP service"
                meta l4proto udp @th,15,16 123 counter accept comment "Accept NTP service"
                meta l4proto { tcp, udp } @th,16,32 2049 counter accept comment "Accept NFS service"
                ip protocol udp udp dport 67 counter accept comment "Accept DHCP service"

                ip saddr 10.0.0.0/8 tcp dport ssh ct state new accept comment "Accept SSHD on port 22"
                tcp dport @custom_accept counter accept comment "Accept for custom reles"

                ip saddr 10.0.0.0/8 tcp dport { 3389,9090,10000} accept comment "Accept administrators WebUI"
                ip saddr 10.0.0.0/8 tcp dport { 5000,5647,8000,8140,8443,9090} accept comment "Accept Katello Agent"

                meta l4proto { tcp, udp } @th,16,16 1918 accept comment "Accept ITM service"
                tcp dport { 1919,1920,3660,6014,10110,14206,15001} accept comment "Accept ITM Agent"

                tcp dport { 443,1556,2821,5432,9000,9001,10082,10102,13720,13724,13782} accept comment "Accept NETBACKUP Agent"

        }

        chain forward {
                type filter hook forward priority 0; policy drop;
                oifname != "lo" ip saddr 127.0.0.1 counter drop
                oifname != "lo" ip daddr 127.0.0.1 counter drop
                oifname lo accept comment "Accept any localhost traffic"
        }

        chain output {
                type filter hook output priority 0; policy accept;
        }

}

