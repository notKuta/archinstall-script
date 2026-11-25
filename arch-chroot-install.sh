#!/bin/bash

## Time

lsblk -f

printf "Which drive was chosen for partition beforehand? for ex. /dev/nvme0n1 or /dev/sda: "
read drive
: "${drive:?"Missing drive"}"

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
    cmdline: rd.luks.name=$(blkid -s UUID -o value "${drive}"p2)=root root=/dev/mapper/root rw rootflags=subvol=/@
    module_path: boot():/initramfs-linux.img
EOF

# Systemd Units

systemctl enable NetworkManager

# Reboot / Exit Chroot

exit
