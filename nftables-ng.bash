cat /etc/nftables/custome-ruleset.nft
#!/usr/sbin/nft -f
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com>
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

