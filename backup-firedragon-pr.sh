#!/usr/bin/env bash
# backupFiredragonProfile.sh
# Safely backs up the Firedragon profile to the USB flash drive with verification.

set -euo pipefail

SRC_DIR="/home/garuda/.firedragon"
DEST_DIR="/mnt/usb/Profiles/.firedragon"
TMP_DIR="/mnt/usb/Profiles/.firedragon_tmp"
OLD_DIR="/mnt/usb/Profiles/.firedragon_old"

# 1. Sanity Check: Ensure Firedragon is not running
if pgrep -x "firedragon" > /dev/null; then
    echo "[-] WARNING: Firedragon is currently running."
    echo "    Backing up preferences while the browser is open can result in inconsistent data."
    read -r -p "    Do you want to close Firedragon and continue? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "[*] Closing Firedragon processes..."
        killall -15 firedragon || true
        sleep 3
        if pgrep -x "firedragon" > /dev/null; then
            echo "[!] Warning: Firedragon did not close cleanly. Force-closing..."
            killall -9 firedragon || true
            sleep 1
        fi
    else
        echo "[*] Aborted. Please close Firedragon and rerun the script."
        exit 1
    fi
fi

# 2. Verify Source Directory Existence
if [ ! -d "$SRC_DIR" ]; then
    echo "[!] Error: Source Firedragon directory not found at $SRC_DIR."
    exit 1
fi

# Ensure the destination parent directory exists
mkdir -p "/mnt/usb/Profiles"

# Clean up any leftover temporary directories from failed previous runs
if [ -d "$TMP_DIR" ]; then
    echo "[*] Cleaning up leftover temporary directory from a previous run..."
    rm -rf "$TMP_DIR"
fi

# 3. Transfer Data to Temporary Directory
echo "[*] Starting transfer of Firedragon profile to temporary directory..."
echo "    Source: $SRC_DIR"
echo "    Temporary Destination: $TMP_DIR"
echo "--------------------------------------------------"

# Note: Since the USB drive filesystem is exfat, we must avoid preserving Unix permissions,
# owners, groups, and symlinks (which exfat doesn't support).
# -rtD: recursive, preserve times, preserve devices
# --no-links: skip symlinks entirely (prevents failing on lock links)
# --no-perms --no-owner --no-group: skip unix permission mapping
rsync -rtDcihP --no-links --no-perms --no-owner --no-group --info=name0 --info=progress2 --info=stats2 --delete "$SRC_DIR/" "$TMP_DIR/"

echo "--------------------------------------------------"
echo "[*] Transfer finished. Verifying data integrity..."

# 4. Verification Step
# Perform a dry-run rsync verification check to ensure the source and temporary copy are identical.
# We filter out the 'skipping non-regular file' warning lines to only capture actual differences.
verify_diff=$(rsync -rtDci --no-links --no-perms --no-owner --no-group --dry-run "$SRC_DIR/" "$TMP_DIR/" | grep -v 'skipping non-regular file' || true)

if [ -n "$verify_diff" ]; then
    echo "[!] Integrity Error: Differences detected between source and copied files!"
    echo "    Differences found:"
    echo "$verify_diff"
    echo "    Aborting swap. Your old backup has NOT been modified."
    exit 1
fi

echo "[+] Verification successful: Temporary copy matches source exactly."

# 5. Swap Directories Atomically
echo "[*] Replacing the old backup with the newly verified copy..."

# Delete any old backup path that shouldn't be there
if [ -d "$OLD_DIR" ]; then
    rm -rf "$OLD_DIR"
fi

# Rename the existing backup folder to _old (so we don't overwrite it directly)
if [ -d "$DEST_DIR" ]; then
    mv "$DEST_DIR" "$OLD_DIR"
fi

# Swap the newly verified copy into place
mv "$TMP_DIR" "$DEST_DIR"

# Now safely remove the old backup folder
if [ -d "$OLD_DIR" ]; then
    rm -rf "$OLD_DIR"
fi

echo "[+] Success! The Firedragon profile has been successfully backed up, verified, and updated."
