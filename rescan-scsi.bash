#!/usr/bin/env bash
# Scan new SCSI device.
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

for BUS in /sys/class/scsi_host/host*/scan
do
   echo "- - -" >  ${BUS}
done
#End
exit 0