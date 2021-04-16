#!/usr/bin/env bash
# The file we will be editing DNS zone.
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
#*********************************************************************************************************************
#.vim plugin
#function! UPDSERIAL(date, num)
#if (strftime("%Y%m%d") == a:date)
#return a:date . a:num+1
#endif
#return strftime("%Y%m%d") . '01'
#endfunction
#
#command Soa :%s/\(2[0-9]\{7}\)\([0-9]\{2}\)\(\s*;\s*Serial\)/\=UPDSERIAL(subm atch(1), submatch(2)) . submatch(3)/gc
#*********************************************************************************************************************

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

# Additional functions for this shell script
MINARG=2

function print_usage_short {
    echo "Get help: \"$0 <domain> <file zone>\" or for more information (-h | --help)"
}

function print_usage {
cat <<EOF
Use this script:"$0 <domain> <file zone>"
The script support text and raw format zone file.
The script automatically changes the serial number of the zone and creates a backup copy in the "/tmp" directory <file name>.<current date>

For manual convert format zone file:
Convert raw zone file "example.net.raw", containing data for zone example.net, to text-format zone file "example.net.text": 
$ named-compilezone -f raw -F text -o example.net.text example.net example.net.raw
Convert text format zone file "example.net.text", containing data for zone example.net, to raw zone file "example.net.raw": 
$ named-compilezone -f text -F raw -o example.net.raw example.net example.net.text
EOF
}

if  [[ $1 == "-h" ]] || [[ $1 == "--help" ]]; then
    print_usage
    exit 1
    else
    if [ $# -lt "$MINARG" ] ; then
    print_usage_short
    exit 1
    fi
fi

PACKAGES=( bash )
# Define some default values for this script
DOMAIN=$1
FILE=$2
ZCONV='False'
DATE=$(date +%Y%m%d)
SERNUM=$(grep -m 1 -o -hE '[0-9]{9,10}' $FILE)
SERTMP="${DATE}00"
SERNEW=''
BIND=''
CHROOT='named-chroot.service'
NOCHROOT='named.service'

# Export LANG so we get consistent results
# For instance, fr_FR uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

# initialize PRINT_* counters to zero
pass_count=0 ; invalid_count=0 ; fail_count=0 ; success_count=0

function pad {
  PADDING="..............................................................."
  TITLE=$1
  printf "%s%s  " "${TITLE}" "${PADDING:${#TITLE}}"
}

function print_INVALID {
  echo -e "$@ \e[1;33mINVALID\e[0;39m\n"
  let exist_count++
  return 0
}

function print_PASS {
  echo -e "$@ \e[1;32mPASS\e[0;39m\n"
  let pass_count++
  return 0
}

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

function panic {
  local error_code=${1} ; shift
  echo "Error: ${@}" 1>&2
  exit ${error_code}
}

# Conver RAW to TEXT or creat backup file ZONE.
if file ${FILE} | grep -e 'data$'; then
named-compilezone -f raw -F text -o ${FILE}.${DATE}.bak ${DOMAIN} ${FILE} > /dev/null 2>&1 && ZCONV='True'
else
cp -p ${FILE} ${FILE}.${DATE}.bak > /dev/null 2>&1
fi

[[ ! -f ${FILE}.${DATE}.bak ]] && panic 1 "${FILE}.${DATE}.bak does not exist"

# Run VIM in sudo to open the file.
vim -c ":set tabstop=8" -c ":set shiftwidth=8" -c ":set noexpandtab" ${FILE}.${DATE}.bak
echo ""
pad "Editing $FILE"
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

# Force decimal representation, increment.
if [ "${SERNUM}" -lt "${DATE}00" ]; then
    SERNEW="${DATE}01"
else
    PREFIX=${SERNUM::-2}
    if [ "${DATE}" -eq "${PREFIX}" ]; then
      NUM=${SERNUM: -2}
      NUM=$((10#$NUM + 1))
      SERNEW="${DATE}$(printf '%02d' $NUM )"
    else
     SERNEW="${SERTMP}"
    fi
fi
pad "Change serial number:"
awk '/'${SERNUM}'/ && !done { sub(/'${SERNUM}'/, "'${SERNEW}'"); done=1}; 1' ${FILE}.${DATE}.bak > ${FILE}.tmp
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

# Sanity check
pad "Sanity check:"
named-checkzone $DOMAIN ${FILE}.tmp > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_INVALID
    echo -n "Sanity check failed, reverting to old SOA:"
    rm -f ${FILE}.${DATE}.bak && rm -f ${FILE}.tmp;
    exit 1
else
    print_PASS
fi

# Continue to automatic functionality.
function data_MODIF {
  if [[ ZCONV == "True" ]] ; then
  named-compilezone -f text -F raw -o ${FILE}.tmp ${DOMAIN} ${FILE} > /dev/null 2>&1
  chown :named ${FILE}
  else
  mv ${FILE}.tmp ${FILE}
  chown :named ${FILE}
    if [[ "${FILE}" =~ ^/* ]]; then
    MFILE=$(echo ${FILE} | grep -o -hE "[-.a-z0-9]*$")
    mv ${FILE}.${DATE}.bak /tmp/${MFILE}.${DATE}
    else
    mv ${FILE}.${DATE}.bak /tmp/${FILE}.${DATE}
    fi
  fi
}

read -p "Ready to commit? " choice
    while :
      do
        case "$choice" in
            y|Y) data_MODIF; break;;
            n|N) echo -e "\nChanges will not be automatically committed, exiting."; exit;;
            * ) read -p "Please enter 'y' or 'n': " choice;;
          esac
      done
echo ""

# Restart BIND 
pad "Restarting BIND:"
function binding {
  for SERV in {$CHROOT,$NOCHROOT}
  do
  systemctl is-active $SERV > /dev/null && BIND="$SERV" && return 0
  done
  echo Error! No service is active.
  return 1
}
binding && rndc flush && rndc reload > /dev/null 2>&1
if [ $? -ne 0 ]; then
    exit 1
else
    print_SUCCESS
fi

#END
exit 0
