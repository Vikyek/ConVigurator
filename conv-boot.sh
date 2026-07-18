#!/usr/bin/env bash
# conv-boot.sh
# System configuration tuner to adjust services dynamically on boot.
# Checks for touchscreens and Btrfs layouts, then scales services.
set -euo pipefail

echo "=========================================="
echo "    ConVigurator Boot Configuration Tuner"
echo "=========================================="

# 1. Check for Touchscreen and configure evdev-rce
echo -e "\n[*] Auditing Touchscreen interface..."
if udevadm info --export-db | grep -q "ID_INPUT_TOUCHSCREEN=1"; then
    echo "    [+] Touchscreen detected. Enabling evdev-rce.service..."
    systemctl enable --now evdev-rce.service || true
else
    echo "    [-] No touchscreen detected. Disabling evdev-rce.service..."
    systemctl disable --now evdev-rce.service || true
fi

# 2. Check root filesystem and configure Snapper cleaner
echo -e "\n[*] Auditing root filesystem..."
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
echo "    Root filesystem type is: $ROOT_FSTYPE"
if [ "$ROOT_FSTYPE" = "btrfs" ]; then
    echo "    [+] Btrfs filesystem detected. Enabling snapper-cleanup.timer..."
    systemctl enable --now snapper-cleanup.timer || true
else
    echo "    [-] Non-Btrfs filesystem detected. Disabling snapper-cleanup.timer..."
    systemctl disable --now snapper-cleanup.timer snapper-cleanup.service || true
fi

echo -e "\n[+] Boot tuning complete!"
