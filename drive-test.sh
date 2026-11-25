#!/bin/bash

drive="/dev/sda"
whatDrive=
drive_section=$(printf "${drive}\n" | awk -F '/' '{print $3}' | cut -c 1-4)
if [ "${drive_section}" == "nvme" ]; then
	#mkfs.fat -F 32 -n boot ${drive}p1
	whatDrive="NVME"
else
	#mkfs.fat -F 32 -n boot ${drive}1
	whatDrive="HDD"
fi

echo $whatDrive
