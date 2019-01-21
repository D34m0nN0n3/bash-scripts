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

function print_usage {
    echo "Use this script: \"$0\" \<domain\> \<file zone\> or \-h\|\-\-help"
}

if  [[ $1 == "\-h" ]] || [[ $1 == "\-\-h" ]] ; then
    print_usage
    panic 2
    else
    if [ $# -lt "$MINARG" ] ; then
    print_usage
    panic 2
    fi
fi

PACKAGES=( bash )
# Define some default values for this script
DOMAIN=$1
FILE=$2
DATE=$(date +%Y%m%d)
SERNUM=$(grep -hE '[0-9]{9,10}' $FILE)
SERTMP="${DATE}00"
SERNEW=''
BIND=''

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
  echo -e "$@ \e[1;33mPASS\e[0;39m\n"
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

# Creat backup file ZONE.
cp -p $FILE $FILE$DATE.bak > /dev/null 2>&1
[[ -f $FILE$DATE.bak ]] && panic 1 "${FILE}${DATE}.bak does not exist"

# Run VIM in sudo to open the file.
echo "Editing $FILE..."
vim -c ":set tabstop=8" -c ":set shiftwidth=8" -c ":set noexpandtab" $FILE
echo -e "\t\t[OK]"
echo ""
# Check to make sure the syntax is correct before continuing.
pad "Syntax check:"
named-checkzone $DOMAIN $FILE > /dev/null 2>&1
if [ $? -ne 0 ]; then 
    print_INVALID
    exit 1
else
    print_PASS
fi
# Continue to automatic functionality.
read -p "Ready to commit? (y/n): " -e continue
if [ "$continue" != "y" ]; then
    echo "Changes will not be automatically committed, exiting."
    exit
fi
echo ""
# Force decimal representation, increment.
if [ ${SERNUM} -lt ${DATE}00 ]; then
    SERNEW="${DATE}01"
else
    PREFIX=${SERNUM::-2}
    if [ ${DATE} -eq ${PREFIX} ]; then
      NUM=${SERNUM: -2}
      NUM=$((10#$NUM + 1))
      SERNEW="${DATE}$(printf '%02d' $NUM )"
    else
     SERNEW="${SERTMP}"
    fi
fi
pad "Change serial number:"
sed -i -e 's/'"$SERNUM"'/\t'"$SERNEW"'/' $FILE
if [ $? -ne 0 ]; then 
    print_FAIL
    exit 1
else
    print_SUCCESS
fi
# Sanity check
pad "Sanity check:"
named-checkzone $DOMAIN $FILE > /dev/null 2>&1
if [ $? -ne 0 ]; then
    print_INVALID
    echo -n "Sanity check failed, reverting to old SOA:"
    mv $FILE$DATE.bak $FILE
    exit 1
else
    print_PASS
    rm -f $FILE$DATE.bak
fi

# Restart BIND 
pad "Restarting BIND:"
	for SERV in named.service named-chroot.service
	do
	systemctl is-active $SERV > /dev/null && BIND="$SERV" && return 0
	done
	echo Error! No service is active.
	return 1
systemctl restart $BIND > /dev/null
if [ $? -ne 0 ]; then
    print_FAIL
    exit 1
else
    print_SUCCESS
fi

#END
exit 0
