#!/usr/bin/env bash
# This script install ISC BIND (https://www.isc.org/downloads/bind/) server.
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

# Define some default values for this script
PACKAGES=( bash )
BIND='null'
ENSERV='named-chroot.service'
DISSERV='named.service'

# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

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

# Install ISC BIND DNS
function install_bind {
pad "Install BIND server:"

yum install bind bind-utils bind-chroot -y > /dev/null 2>&1
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi

cat <<'EOF' >> /etc/sysconfig/named > /dev/null 2>&1
OPTIONS="-4"
EOF

mkdir -p /var/named/masters && chmod u=rwx,g=rx /var/named/masters && chown root:named /var/named/masters &&
chcon -t named_zone_t /var/named/* &&
chcon -t named_conf_t /etc/{named,rndc}.* &&
chcon -t named_cache_t /var/named/{masters,slaves,data} &&
setsebool -P named_write_master_zones 1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi

systemctl start named-setup-rndc.service && systemctl status named-setup-rndc.service > /dev/null 2>&1
restorecon -v /etc/rndc.* /etc/named.* > /dev/null 2>&1
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi

for DISNAMED in {stop,disable,mask}; do systemctl ${DISNAMED} ${DISSERV} > /dev/null 2>&1; done
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi

for ENANAMED in {start,enable}; do systemctl ${ENANAMED} ${ENSERV} > /dev/null 2>&1; done
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi

if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

# Create base configuration files ISC BIND DNS (/etc/named.conf, /etc/named/views.conf, /etc/named/zones.conf, /var/named/blockeddomain.hosts)
function base_config {
read -p "Enter administrators server contact phone number [+7(xxx)xxx-xx-xx]: " -e number
echo -e "\n[\e[1;32mDONE\e[0;39m]\n"

cat <<EOF > /etc/named.conf
options {
      hostname                     none;
      version                      "Administrators contact: ph. ${number}";
      listen-on port 53            { 127.0.0.1; any; };
      listen-on-v6 port 53         { none; };
      directory                    "/var/named";
      dump-file                    "/var/named/data/cache_dump.db";
      statistics-file              "/var/named/data/named_stats.txt";
      memstatistics-file           "/var/named/data/named_mem_stats.txt";
      memstatistics                yes;
      zone-statistics              yes;
      max-cache-size               256M;
      max-journal-size             500M;
      cleaning-interval            60;
      allow-query                  { localhost; localnets; 10/8; };
      allow-transfer               { localhost; localnets; };
      allow-update                 { localhost; localnets; };
      allow-query-on               { localhost; localnets; 10/8; };
      allow-query-cache-on         { localhost; localnets; 10/8; };
      transfer-source              * port 53;
      notify-source                * port 53;
      notify                       explicit;
      transfer-format              many-answers;
      minimal-responses            yes;
      empty-zones-enable           yes;
      flush-zones-on-shutdown      yes;
      auth-nxdomain                no;    # conform to RFC1035

 /*       
      zero-no-soa-ttl              yes;
      zero-no-soa-ttl-cache        yes;
*/

      dnssec-enable                yes;
      dnssec-validation            auto;
      dnssec-lookaside             auto;

      rate-limit		 { responses-per-second 10;
				   referrals-per-second 5;
				   nodata-per-second 5;
                                   errors-per-second 5;
                                   all-per-second 20;
                                   min-table-size 500;
                                   max-table-size 20000;
                                   slip 2;
                                   window 15;
                                   qps-scale 250;
                                   log-only yes; 
                                   };

      pid-file                    "/run/named/named.pid";
      session-keyfile             "/run/named/session.key";
      managed-keys-directory      "/var/named/dynamic";

      /* Path to ISC DLV key */
      bindkeys-file               "/etc/named.iscdlv.key";
};        
 
    include                       "/etc/rndc.key";
    include                       "/etc/named.root.key";

controls  {
      inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
};

logging {

      category default         { default_log; };
      category config          { default_log; };
      category security        { security_log; };
      category xfer-in         { xfer_log; };
      category xfer-out        { xfer_log; };
      category notify          { notify_log; };
      category update          { update_log; };
      category queries         { default_log; };
      category client          { default_log; };
      category lame-servers    { lame_servers_log; };
      category dnssec          { dnssec_log; };
      category update          { ddns_log; };
      category update-security { ddns_log; };
      category rate-limit      { rate_limiting_log; };
      category rpz             { rpz_log; };
      category queries         { query_errors_log; };
      category query-errors    { query_errors_log; };
        
      channel default_debug {
            file "data/named.run" versions 5 size 100M;
            severity dynamic;
      };

      channel default_log {
            file "/var/log/default.log" versions 3 size 100M;
            severity info;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel security_log {
            file "/var/log/security.log" versions 3 size 100M;
            severity warning;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel xfer_log {
            file "/var/log/xfer.log" versions 3 size 100M;
            severity error;
            print-category yes;
            print-severity yes;
            print-time yes;
      };    
      channel notify_log {
            file "/var/log/notify.log" versions 3 size 100M;
            severity notice;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel update_log {
            file "/var/log/update.log" versions 3 size 100M;
            severity warning;
            print-category yes;
            print-severity yes;
            print-time yes;
      };        
      channel lame_servers_log {
            file "/var/log/lame-servers.log" versions 3 size 100M;
            severity notice;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel dnssec_log {
            file "/var/log/dnssec.log" versions 3 size 20M;
            severity info;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel ddns_log {
            file "/var/log/ddns.log" versions 3 size 20M;
            severity info;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel rate_limiting_log {
            file "/var/log/rate-limiting.log" versions 5 size 50M;
            severity info;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel rpz_log {
            file "/var/log/rpz.log" versions 3 size 100M;
            severity info;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
      channel query_errors_log {
            file "/var/log/query-errors.log" versions 5 size 50M;
            severity dynamic;
            print-category yes;
            print-severity yes;
            print-time yes;
      };
};

include "/etc/named/views.conf";

//END
EOF

cat <<'EOF' > /etc/named/views.conf
acl work {
	10/8;
	};
	
acl internal {
        10/8;
        };

view "internal" {
      match-clients {
        internal;
        };
      allow-query {
        internal;
        };
      allow-recursion {
        internal;
        };
      recursion yes;
      additional-from-auth yes;
      additional-from-cache yes;
      forward first;
      forwarders {
	10.248.0.180;
	10.248.0.181;
	};
			
      response-policy { zone "blockeddomain.hosts"; 
	  zone "dbl.rpz.spamhaus.org" policy nxdomain;
	  zone "botnetcc.rpz.spamhaus.org" policy nodata;
	  zone "malware-adware.rpz.spamhaus.org" policy nodata;
	  zone "malware-aggressive.rpz.spamhaus.org" policy nodata;
	  zone "drop.rpz.spamhaus.org" policy nodata; 
	  };
		
zone "blockeddomain.hosts" IN {
      type master;
      file "/var/named/blockeddomain.hosts";
      allow-update { none; };
      };
				
zone "dbl.rpz.spamhaus.org" {
	type slave;
	file "/var/named/slaves/dbl.rpz.spamhaus.org";
	masters { 34.194.195.25; 35.156.219.71; };
	allow-transfer { none; };
	};

zone "botnetcc.rpz.spamhaus.org" {
	type slave;
	file "/var/named/slaves/botnetcc.rpz.spamhaus.org";
	masters { 34.194.195.25; 35.156.219.71; };
	allow-transfer { none; };
	};

zone "malware-adware.rpz.spamhaus.org" {
	type slave;
	file "/var/named/slaves/malware-adware.rpz.spamhaus.org";
	masters { 34.194.195.25; 35.156.219.71; };
	allow-transfer { none; };
	};
					
zone "malware-aggressive.rpz.spamhaus.org" {
	type slave;
	file "/var/named/slaves/malware-aggressive.rpz.spamhaus.org";
	masters { 34.194.195.25; 35.156.219.71; };
	allow-transfer { none; };
	};

zone "drop.rpz.spamhaus.org" {
	type slave;
	file "/var/named/slaves/drop.rpz.spamhaus.org";
	masters { 34.194.195.25; 35.156.219.71; };
	allow-transfer { none; };
	};

include                       "/etc/named.rfc1912.zones";				
include                       "/etc/named/zones.conf";

zone "." IN {
      type hint;
      file "named.ca";
      };

};

acl external {
        <ACL-ROLE>;
        };

view "external" {
      match-clients {
        external;
        };
      allow-query {
        external;
        };
      recursion no;
      additional-from-auth no;
      additional-from-cache no;

include                       "/etc/named/zones.conf";

};

//END
EOF

cat <<'EOF' > /etc/named/zones.conf
# Zone inventory
EOF

cat <<EOF > /var/named/blockeddomain.hosts
\$TTL   86400 ; one day

@       IN      SOA     ${HOSTNAME}. postmaster.domain (
                          1
                          28800   ; refresh  8 hours
                          7200    ; retry    2 hours
                          864000  ; expire  10 days
                          86400 ) ; min ttl  1 day
		
                        NS      ${HOSTNAME}.

; QNAME policy records.
; (.) - возврат NXDOMAIN
; (*.) - возврат NODATA
; (rpz-drop.) - сервер игнорирует запрос
; (rpz-passthru.) - ответ DNS-сервера не модифицируется
; (rpz-tcp-only.) - вынуждает клиента выполнить запрос по TCP

\$TTL   86400 ; 1 day
                        TXT     "Administrators contact: ph. ${number}"

*               IN      CNAME       rpz-passthru.
;END
EOF
}

function check_base_config {
pad "Create base BIND configuration:"
if [ ! -f /etc/named.conf ]; then
let warning_count++
fi
let success_count++
if [ ! -f /etc/named/views.conf ]; then
let warning_count++
fi
let success_count++
if [ ! -f /etc/named/zones.conf ]; then
let warning_count++
fi
let success_count++
if [ ! -f /var/named/blockeddomain.hosts ]; then
let warning_count++
fi
let success_count++

if [ ${warning_count} -ne 0 ]; then
    print_WARNING
else
    print_SUCCESS
fi
}

# Authoritative nameserver BIND 
function any_bind {
sed -i 's,<ACL-ROLE>,any,' /etc/named/views.conf > /dev/null 2>&1
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi
}

# Recursive resolver BIND 
function none_bind {
sed -i 's,<ACL-ROLE>,none,' /etc/named/views.conf > /dev/null 2>&1
if [ $? -ne 0 ]; then
    let fail_count++
else
    let success_count++
fi
}

# Check config status BIND server 
function check_status {
pad "Check BIND status:"
named-checkconf && rndc status > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

# Run VIM in sudo to open the file.
function manual_edit {
read -p "Enter file to edit: " -e file
vim -c "set pastetoggle=<F12>" -c ":set tabstop=8" -c ":set shiftwidth=8" -c ":set noexpandtab" -c "set backupcopy=yes" ${file}
echo -e "\n[\e[1;32mDONE\e[0;39m]\n"
}

# Restart BIND 
function restart_bind {
pad "Restarting BIND:"
function binding {
	for SERV in {$ENSERV,$DISSERV}
	do
	systemctl is-enabled $SERV > /dev/null && BIND="$SERV" && return 0
	done
	echo Error! No service is active.
	return 1
}
binding && systemctl restart $BIND > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
}

PS3='Select action: '
options=("Authoritative nameservers answer to resource records that are part of their zones only." "Recursive nameservers offer resolution services, but they are not authoritative for any zone." "For edit manual the main configuration file." "Check configuration and status." "Quit")
        select opt in "${options[@]}"
        do
        case $opt in
                "Authoritative nameservers answer to resource records that are part of their zones only.") install_bind; base_config; check_base_config; any_bind; restart_bind; continue;;
                "Recursive nameservers offer resolution services, but they are not authoritative for any zone.") install_bind; base_config; check_base_config; none_bind; restart_bind; continue;;
                "For edit manual the main configuration file.") manual_edit; exit;;
                "Check configuration and status.") check_status; exit;;
                "Quit") break;;
                *) echo "Invalid option. Try another one."; continue;;
        esac
        done

#END
exit 0
