#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Scan new SCSI device.

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

BUSSES=$(ls -l /sys/class/scsi_host/host* | grep -o host[0-9] | uniq)
DEVICES=$(ls /sys/class/scsi_device/)

for DEVICE in ${DEVICES}
do
  echo "RESCANNING DEVICE : ${DEVICE}"
  echo 1 > /sys/class/scsi_device/${DEVICE}/device/rescan
done

for BUS in ${BUSSES}
do
   echo "RESCANNING HOST BUS : ${BUS}"
   echo "- - -" > /sys/class/scsi_host/${BUS}/scan
done
#End
exit 0
