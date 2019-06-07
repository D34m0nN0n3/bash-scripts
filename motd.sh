#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com>
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Message of the day.
PSA=`ps -Afl | wc -l`
HOSTNAME=$(uname -n)
KERNEL=$(uname -r)
# Time of day
CLOCK=$(date +"%H:%M")
HOUR=$(date +"%H")
if [ $HOUR -lt 12  -a $HOUR -ge 6 ]; then TIME="morning"
elif [ $HOUR -lt 17 -a $HOUR -ge 12 ]; then TIME="afternoon"
elif [ $HOUR -lt 24 -a $HOUR -ge 17 ]; then TIME="evening"
else TIME="nigth"
fi
#System uptime
uptime=`cat /proc/uptime | cut -f1 -d.`
upDays=$((uptime/60/60/24))
upHours=$((uptime/60/60%24))
upMins=$((uptime/60%60))
upSecs=$((uptime%60))
echo -e ""
echo -e "Good ${TIME}! Welcome ${USER} to SERVER: ${HOSTNAME}! Current time: ${CLOCK}"
echo -e "
OS version..........: `cat /etc/*-release | awk 'NR==1'`
Kernel version......: ${KERNEL}
System uptime.......: $upDays days $upHours hours $upMins minutes $upSecs seconds
Processes...........: $PSA running
Users...............: Currently `users | wc -w` user(s) logged on
"
echo -e ""
echo -e "The last five kernel messages in the log:"
journalctl -k -b -n 5 | awk '{print}'
echo -e ""
echo -e "The last five error messages in the log:"
journalctl -p err -b -n 5 | awk '{print}'
echo -e ""
echo -e "System updates: ${UPDATES_SEC_COUNT} package(s) needed for security, out of ${UPDATES_COUNT} available."
echo -e ""
if [ ${UPDATES_COUNT} -ne 0 ]
  then echo -e 'Run "sudo yum update" to apply all updates!'
  else echo -e 'System update is not required!'
fi
