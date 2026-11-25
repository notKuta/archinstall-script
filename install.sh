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
	partDrive="${drive}p2"
else
	whatDrive="HDD"
	partDrive="${drive}2"
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

sleep 3

lsblk -f

# BTRFS-specific section

mount /dev/mapper/root /mnt/ -o subvolid=5

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@swap
btrfs subvolume create /mnt/@portables
btrfs subvolume create /mnt/@machines

umount /mnt/

mount -o compress=zstd,subvol=/@ /dev/mapper/root /mnt/
mount -o compress=zstd,subvol=/@home --mkdir /dev/mapper/root /mnt/home
mount -o compress=zstd,subvol=/@root --mkdir /dev/mapper/root /mnt/root
mount -o compress=zstd,subvol=/@srv --mkdir /dev/mapper/root /mnt/srv
mount -o compress=zstd,subvol=/@cache --mkdir /dev/mapper/root /mnt/var/cache
mount -o compress=zstd,subvol=/@tmp --mkdir /dev/mapper/root /mnt/var/tmp
mount -o compress=zstd,subvol=/@log --mkdir /dev/mapper/root /mnt/var/log
mount -o compress=zstd,subvol=/@snapshots --mkdir /dev/mapper/root /mnt/.snapshots
mount -o compress=zstd,subvol=/@swap --mkdir /dev/mapper/root /mnt/.swap
mount -o compress=zstd,subvol=/@portables --mkdir /dev/mapper/root /mnt/var/lib/portables
mount -o compress=zstd,subvol=/@machines --mkdir /dev/mapper/root /mnt/var/lib/machines

if [ "${whatDrive}" == "NVME" ]; then
        mount --mkdir ${drive}p1 /mnt/boot
else
        mount --mkdir ${drive}1 /mnt/boot
fi

# Reflector / Mirrors

reflector --latest 5 --protocol https --age 12 --sort rate --save /etc/pacman.d/mirrorlist

# Pacstrap / Packages

## Checks if CPU is Intel or AMD

whatCPU=$(lscpu | awk -F ':' '/^Model name/ {print $2}' | awk '{print $1}')

if [ "${whatCPU}" == "AMD" ]; then
	pacstrap -K /mnt amd-ucode base linux linux-firmware btrfs-progs dosfstools networkmanager nano neovim man-db man-pages texinfo tealdeer git limine
else
	pacstrap -K /mnt intel-ucode base linux linux-firmware btrfs-progs dosfstools networkmanager nano neovim man-db man-pages texinfo tealdeer git limine
fi

# Configure System

## Fstab

genfstab -U /mnt >> /mnt/etc/fstab

cat /mnt/etc/fstab

printf "Does this look correct? (y or n): "
read answer2

if [ "${answer2}" == "n" ]; then
	vim /mnt/etc/fstab
fi

## Chroost

arch-chroot -S /mnt

## Time

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

hwclock --systohc

## Localization 

sed "s/\#en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/g" /etc/locale.gen > /etc/tmp && mv /etc/tmp /etc/locale.gen
locale-gen
touch /etc/locale.conf
echo "LANG=en_US.UTF-8" > /etc/locale.conf

## Hostname

printf "Enter Hostname: "
read hostname
: "${hostname:?"Missing hostname"}"

echo ${hostname} > /etc/hostname

## mkinicpio for encryption

hookLine=$(awk '/^HOOKS/ {print $0}' /etc/mkinitcpio.conf)
desiredHookLine="HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)"

sed "s/${hookLine}/${desiredHookLine}/" /etc/mkinitcpio.conf > /etc/tmp && mv /etc/tmp /etc/mkinitcpio.conf

mkinitcpio -P

# Password

printf "Password: "
read -s password
echo
printf "Repeat Password: "
read -s password2
echo
[[ "$password" == "$password2" ]] || ( printf "Passwords did not match\n"; exit 1; )

# Bootloader

mkdir -p /boot/EFI/arch-limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/arch-limine/

efibootmgr \
      --create \
      --disk ${drive} \
      --part 1 \
      --label "Arch Linux Limine Boot Loader" \
      --loader '\EFI\arch-limine\BOOTX64.EFI' \
      --unicode

touch /boot/EFI/arch-limine/limine.conf

cat <<EOF > /boot/EFI/arch-limine/limine.conf 
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx rw
    module_path: boot():/initramfs-linux.img
EOF

#
# EVERYTHING BETWEEN THE DASHED LINES MUST BE CHECKED IN
# A TEST FILE FOR CORRECTNESS; IT CURRENTLY DOES NOT WORK
#

# ----------------------------------------------------------------------
 
uuidLine=$( lsblk -f | awk '/${device}p2/ {print $0}' )

cmdLineScript=$(awk '/^cmdline/ {print $0}' /boot/EFI/arch-limine/limine.conf )
desiredCmdLineScript="rd.luks.name=${uuidLine}=root root=/dev/mapper/root rw rootflags=subvol=/@"

sed "s/${cmdLineScript}/${desiredCmdLineScript}/" /boot/EFI/arch-limine/limine.conf > /boot/EFI/arch-limine/tmp && mv /boot/EFI/arch-limine/tmp /boot/EFI/arch-limine/limine.conf 

# ----------------------------------------------------------------------

# Systemd Units

systemctl enable NetworkManager

# Reboot / Exit Chroot

exit
cd
umount -R /mnt
reboot
