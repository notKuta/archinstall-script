#!/bin/bash

################ Gather information from the user ####################

hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

# Checks if internet is connected, if not, queries
# the user to connect to a Wi-Fi network

### Checks if time is synchronized ###
timeSync=$(timedatectl | awk -F ':' '/^System clock synchronized/  {print $2}' )
if [ $timeSync == "no" ]; then
	printf "ERROR: time is not synchronized. Fixing now. Re-run the script.\n"\
	timedatectl set-ntp true
	exit 1
fi

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_root="$(ls ${device}* | grep -E "^${device}p?2$")"

wipefs --all -f ${part_boot}
wipefs --all -f ${part_root}
sfdisk --delete ${device}

##### Partitions a 4 GiB boot partition & rest to root ######
fdisk $drive << EOF &> /dev/null
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

######## Encryption ########

printf "Initializing encryption setup now...\n\n"

printf "WARNING: Use a sufficiently secure password. Even though the keyslot will\n" 
printf "be wiped later, SSD wear-leveling can cause it to persist after removal for\n"
printf "an indefinite amount of time.\n\n"

cryptsetup luksFormat ${part_root}
cryptsetup open ${part_root} root

######### Filesystem creation ##########

mkfs.btrfs -L arch /dev/mapper/root &> /dev/null
mkfs.fat -F 32 -n boot ${part_boot} &> /dev/null

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

mount --mkdir ${part_boot} /mnt/boot

######### Reflector / Mirrors ###########

reflector --latest 5 --protocol https --age 12 --sort rate --save /etc/pacman.d/mirrorlist

######### Pacstrap / Packages ###########

###### Checks if CPU is Intel or AMD ######

CPU=$(lscpu | grep 'Model name' | cut -f 2 -d ":" | awk '{print $1}')

if [[ "${CPU}" == "AMD" ]]; then
	pacstrap -K /mnt amd-ucode base linux linux-firmware btrfs-progs dosfstools networkmanager nano neovim man-db man-pages texinfo tealdeer git limine gamemode sudo
else
	pacstrap -K /mnt intel-ucode base linux linux-firmware btrfs-progs dosfstools networkmanager nano neovim man-db man-pages texinfo tealdeer git limine gamemode sudo
fi

######### Configure System #########

############# Fstab ################

genfstab -U /mnt >> /mnt/etc/fstab

############# Chroot ###############

arch-chroot -S /mnt /bin/bash << END
#!/bin/bash
############ Time ###############

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

hwclock --systohc

######### Localization ##########

sed "s/\#en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/g" /etc/locale.gen > /etc/tmp && mv /etc/tmp /etc/locale.gen
locale-gen
touch /etc/locale.conf
echo "LANG=en_US.UTF-8" > /etc/locale.conf

############# hostname ##############

echo ${hostname} > /etc/hostname

####### mkinicpio for encryption #######

hookLine=$(awk '/^HOOKS/ {print $0}' /etc/mkinitcpio.conf)
desiredHookLine="HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)"

sed "s/${hookLine}/${desiredHookLine}/" /etc/mkinitcpio.conf > /etc/tmp && mv /etc/tmp /etc/mkinitcpio.conf

mkinitcpio -P

####### Bootloader ########

mkdir -p /boot/EFI/arch-limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/arch-limine/

efibootmgr \
      --create \
      --disk ${device} \
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
    cmdline: rd.luks.name=$(blkid -s UUID -o value "${part_root}")=root root=/dev/mapper/root rw rootflags=subvol=/@
    module_path: boot():/initramfs-linux.img
EOF

###### Systemd Units ######

systemctl enable NetworkManager

###### USER ######

useradd -mU -g "${user}" -G gamemode,wheel "${user}"

END

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt

# cd
umount -R /mnt

printf "Script Finished!\n\nPlease reboot the system!\n"
