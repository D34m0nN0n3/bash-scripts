#!/usr/bin/env bash
# Copyright (C) 2019 Dmitriy Prigoda <deamon.none@gmail.com> 
# This script is free software: Everyone is permitted to copy and distribute verbatim copies of 
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, but changing it is not allowed.
# Monitoring web sites and servers with OpenID-Connect.

# Export LANG so we get consistent results
# For instance, en_US uses comma (,) as the decimal separator.
export LANG=en_US.UTF-8

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root" 1>&2
   exit 1
fi

# Variables
TMPDIRLOG='/var/tmp'
# Calculated variables
RESULT='null'
TOKEN='null'

# Loop read file
# File in CSV format. Example titel: CLIENTID;USERID;PASSID;URLID;SRVURL
for ENTER in $(cat $1); do
# Readable variables
CLIENTID=$(echo $ENTER | cut -d; -f1)
USERID=$(echo $ENTER | cut -d; -f2)
PASSID=$(echo $ENTER | cut -d; -f3)
URLID=$(echo $ENTER | cut -d; -f4)
SRVURL=$(echo $ENTER | cut -d; -f5)

RESULT=`curl -d "client_id=${CLIENTID}" -d "username=${USERID}" -d "password=${PASSID}" -d "grant_type=password" ${URLID}`
TOKEN=`echo ${RESULT} | sed 's/.*access_token":"\([^"]*\).*/\1/'`

# Print report
curl -H "Authorization: Bearer ${TOKEN}" ${SRVURL} >> ${TMPDIRLOG}/sm-srv-portal-$(date +%Y%m%d).log > /dev/null 2>&1
done

#END
exit $?