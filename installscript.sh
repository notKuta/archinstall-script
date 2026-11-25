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
        echo -n "Choose a station: "
        read station_name
        : "${station_name:?"Missing station input"}"
        iwctl station $station_name get-networks
        echo -n "Choose a network: "
        read network_name
        : "${network_name:?"Missing network input"}"
        iwctl station $station_name connect $network_name
done

# Checks if time is synchronized

if [ timedatectl | awk -F ':' '/^System clock synchronized/  {print $2}' == "no" ]; then
	echo ERROR: time is not synchronized. Please fix this.
	exit 1
else
	echo Time is synchronized!
fi

# Paritioning

lsblk

echo -n Which drive would you wish to partition? for ex. /dev/nvme0n1 or /dev/sda :
read drive
: "${drive:?"Missing drive"}"

while :; do
	echo -n Are you sure? *ALL* data on this drive will be wiped: 
	read answer
	: "${answer:?"Missing answer"}"

	if [ $answer == "yes" || $answer == "y" || $answer == "Y" || $answer == "YES"]; then
		break
	fi
done

echo Wiping drive and paritioning...

sfdisk $drive --delete

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



# Hostname

echo -n "Enter Hostname: "
read hostname
: "${hostname:?"Missing hostname"}"

echo $hostname > /etc/hostname
