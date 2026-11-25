#!/bin/bash

drive="/dev/nvme0n1"

drive_section=printf "${drive}\n" | awk -F '/' '{print $3}' | cut -c 1-4
if [ $drive_section == "nvme" ]; then
	mkfs.fat -F 32 -n boot ${drive}p1
else
	mkfs.fat -F 32 -n boot ${drive}1
fi
