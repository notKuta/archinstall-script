#!/bin/bash

drive=/dev/nvme0n1

uuid=$(blkid -s UUID -o value "${drive}"p2)

echo $uuid
