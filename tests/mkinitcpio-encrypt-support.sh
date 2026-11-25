#!/bin/bash

desiredHookLine="HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)"
sed "s/^HOOKS=.*/${desiredHookLine}/" mkinitcpio.conf > tmp && mv tmp mkinitcpio.conf
