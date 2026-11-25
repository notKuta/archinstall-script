#!/bin/bash

hookLine=$(awk '/^HOOKS/ {print $0}' mkinitcpio.conf)
desiredHookLine="HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)"
# sed "s/${hookLine}/HOOKS=(base\ systemd\ autodetect\ microcode\ modconf\ kms\ keyboard\ sd-vconsole\ block\ sd-encrypt\ filesystems\ fsck)/" > tmp && mv tmp mkinitcpio.conf

sed "s/${hookLine}/${desiredHookLine}/" mkinitcpio.conf > tmp && mv tmp mkinitcpio.conf
