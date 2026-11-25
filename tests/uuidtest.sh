#!/bin/bash

whatDrive="NVME"
drive=/dev/nvme0n1
####################################################
uuidLine=
drive_section_SPECIFIC=$(printf "${drive}\n" | awk -F '/' '{print $3}')

if [ "${whatDrive}" == "NVME" ]; then
	uuidLine=$( lsblk --output NAME,UUID | awk '/nvme\?n\?p2/ {print $0}' )
	echo hello
else
	uuidLine=$( lsblk -f | awk '/${device}2/ {print $0}' )
fi

echo $uuidLine
