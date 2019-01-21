#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Some distributions enable saving previous boot information 
# by default, while others disable this feature.

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

SUDO='/usr/bin/sudo'
JRNLDIR='/var/log/journal'
STORAGE='persistent'

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
  let exist_count++
  return 0
}

function print_SUCCESS {
  echo -e "$@ \e[1;32mSUCCESS\e[0;39m\n"
  let success_count++
  return 0
}

function VERIFY_JCONF {
    pad 'Verify "${JRNLDIR}" directory exist'
    if [[ ! -d "${JRNLDIR}" ]]; then
    print_FAIL "directory does not exist"
    mkdir -p ${JRNLDIR}
    else
    print_PASS
    fi
}

function PAST_BOOTS {
    pad 'Some distributions enable saving previous boot information'
    grep -i "${STORAGE}" /etc/systemd/journald.conf
    RESULT=$?
    if [ "${RESULT}" -qe 0 ]; then
    print_FAIL "past boots enabled"
    else
    sed -i 's,Storage\=auto,Storage\=persistent,' /etc/systemd/journald.conf > /dev/null 2>&1
    print_PASS
    fi
}

function RESTART_JOURN {
    pad 'Restart journald service'
    systemctl force-reload systemd-journald > /dev/null 2>&1
    RESULT=$? 
    if [ "${RESULT}" -ne 0 ]; then
    print_FAIL
    else
    print_PASS
    fi
}

PAST_BOOTS
VERIFY_JCONF
RESTART_JOURN

#END
exit 0
