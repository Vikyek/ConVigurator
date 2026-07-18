#!/bin/bash
set -e

# Configuration (custom-generated for this system)
ROOT_DEV="/dev/sda3"
BOOT_DEV="/dev/sda2"
FS_TYPE="btrfs"

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root (sudo)."
    exit 1
fi

echo "=========================================================="
echo "Offline In-Place LUKS Encryption Script for CachyOS/Arch"
echo "=========================================================="
echo "Target Partition: $ROOT_DEV ($FS_TYPE)"
echo "Boot Partition: $BOOT_DEV"
echo "=========================================================="
echo ""
echo "⚠️ WARNING: This script modifies filesystem headers and re-encrypts"
echo "your root partition in-place. Ensure you have backed up any critical data."
echo ""
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Step 1: Shrinking $FS_TYPE filesystem on $ROOT_DEV by 32MB..."
mkdir -p /tmp/mnt_root
mount "$ROOT_DEV" /tmp/mnt_root
btrfs filesystem resize -32M /tmp/mnt_root
umount /tmp/mnt_root

echo "Step 2: Initializing LUKS2 container on $ROOT_DEV..."
echo "You will be prompted to set the encryption passphrase."
cryptsetup reencrypt --new --encrypt --type luks2 --reduce-device-size 32m --init-only "$ROOT_DEV"

echo "Step 3: Performing background re-encryption of data..."
cryptsetup reencrypt "$ROOT_DEV"

echo "Step 4: Opening encrypted container as 'root'..."
cryptsetup open "$ROOT_DEV" root

echo "Step 5: Mounting root subvolumes and boot partition..."
mount -o subvol=/@ /dev/mapper/root /tmp/mnt_root
mount "$BOOT_DEV" /tmp/mnt_root/boot

mount --bind /dev /tmp/mnt_root/dev
mount --bind /sys /tmp/mnt_root/sys
mount --bind /proc /tmp/mnt_root/proc
mount --bind /run /tmp/mnt_root/run

echo "Step 6: Updating configuration files..."
LUKS_UUID=$(blkid -o value -s UUID "$ROOT_DEV")
echo "Updating /etc/crypttab..."
echo "root UUID=$LUKS_UUID none luks" >> /tmp/mnt_root/etc/crypttab

echo "Updating /etc/default/grub..."
if grep -q "cryptdevice=" /tmp/mnt_root/etc/default/grub; then
    echo "cryptdevice parameter already present in GRUB configuration."
else
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 cryptdevice=UUID='"$LUKS_UUID"':root root=/dev/mapper/root"|' /tmp/mnt_root/etc/default/grub
fi

echo "Step 7: Rebuilding initramfs and GRUB configuration inside chroot..."
chroot /tmp/mnt_root /bin/bash -c "mkinitcpio -P && grub-mkconfig -o /boot/grub/grub.cfg"

echo "Step 8: Cleaning up mounts..."
umount /tmp/mnt_root/boot
umount /tmp/mnt_root/dev
umount /tmp/mnt_root/sys
umount /tmp/mnt_root/proc
umount /tmp/mnt_root/run
umount /tmp/mnt_root

echo "=========================================================="
echo "🎉 Root encryption successfully complete!"
echo "You can now reboot into your fully encrypted installation."
echo "=========================================================="
