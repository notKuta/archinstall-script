#!/bin/bash

# Checks if internet is connected, if not, queries
# the user to connect to a Wi-Fi network

internet_status=1
counter=0
while [ $internet_status -ne 0 ]; do
        ping -q -c1 ping.archlinux.org &> /dev/null
        internet_status=$?

        counter+=1
        if [ $counter -eq 1 ]; then
                continue
        fi

        echo Internet is offline!

        if [ ! $(command -v iwctl) &> /dev/null]; then
                echo ERROR: `iwctl` does not exist on the system.
                exit 1
        fi

        iwctl station list
        printf "Choose a station: "
        read station_name
        : "${station_name:?"Missing station input"}"
        iwctl station $station_name get-networks
        printf "Choose a network: "
        read network_name
        : "${network_name:?"Missing network input"}"
        iwctl station $station_name connect $network_name
done

# Checks if time is synchronized
#
timeSync=$(timedatectl | awk -F ':' '/^System clock synchronized/  {print $2}' )
if [ $timeSync == "no" ]; then
	printf "ERROR: time is not synchronized. Please fix this.\n"
	exit 1
else
	printf "Time is synchronized!\n"
fi

# Paritioning

lsblk

printf "Which drive would you wish to partition? for ex. /dev/nvme0n1 or /dev/sda: "
read drive
: "${drive:?"Missing drive"}"

while :; do
	printf "Are you sure? *ALL* data on this drive will be wiped (y or n):  "
	read answer
	: "${answer:?"Missing answer"}"

	if [ $answer == "y" ]; then
		break
	else
		continue
	fi
done

printf "Wiping drive and paritioning...\n"


wipefs --all -f ${drive}?
sfdisk ${drive} --delete

# Creates a 4 GiB boot partition and reserves the rest of the
# space for the root partition

fdisk $drive << EOF
g
n
1

+4096M
t
uefi
n
2


t
2
23
p
w
EOF

# Encryption

printf "Initializing encryption setup now...\n\n"

printf "WARNING: Use a sufficiently secure password. Even though the keyslot will\n" 
printf "be wiped later, SSD wear-leveling can cause it to persist after removal for\n"
printf "an indefinite amount of time.\n\n"

drive_section=$(printf "${drive}\n" | awk -F '/' '{print $3}' | cut -c 1-4)
whatDrive=
partDrive=
if [ "${drive_section}" == "nvme" ]; then
	whatDrive="NVME"
	partDrive="${device}p2"
else
	whatDrive="HDD"
	partDrive="${device}2"
fi

cryptsetup luksFormat ${partDrive}
# printf "\n\nEnter previous passphrase to open the encrypted volume!\n\n"
cryptsetup open ${partDrive} root

# Filesystem creation

mkfs.btrfs -L arch /dev/mapper/root &> /dev/null

# Checks if drive is an NVME or Sata HDD then makes FAT partition

if [ "${whatDrive}" == "NVME" ]; then
        mkfs.fat -F 32 -n boot ${drive}p1
else
        mkfs.fat -F 32 -n boot ${drive}1
fi

lsblk -f

# Hostname

printf "Enter Hostname: "
read hostname
: "${hostname:?"Missing hostname"}"

echo $hostname > /etc/hostname
