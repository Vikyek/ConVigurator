#!/usr/bin/env bash
# systemSnapshot.sh
# Creates space-efficient, hard-linked incremental snapshots of the live system's overlay upper layer.

set -euo pipefail

# Configuration
OVERLAY_DIR="/run/miso/overlay_root/upper"
BACKUP_ROOT="/mnt/temp/snapshots"
INDEX_LAST="/home/garuda/.config/snapshot_index_last.txt"
INDEX_CURR="/tmp/snapshot_index_current.txt"
AUTO_MODE=false

# Help menu
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --auto      Run automatically without prompting (suitable for cron/systemd)"
    echo "  -h, --help      Show this help message"
}

# Parse options
for arg in "$@"; do
    case "$arg" in
        -a|--auto)
            AUTO_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
    esac
done

echo "[*] Initializing snapshot check..."

# 1. Ensure backup directory is mounted
if ! mountpoint -q /mnt/temp; then
    echo "[!] Error: Backup destination partition /mnt/temp is not mounted."
    if [ "$AUTO_MODE" = false ]; then
        read -r -p "    Would you like to try mounting /dev/sdb1 to /mnt/temp? (y/N): " mount_confirm
        if [[ "$mount_confirm" =~ ^[Yy]$ ]]; then
            sudo mkdir -p /mnt/temp
            sudo mount /dev/sdb1 /mnt/temp
        else
            echo "[!] Aborted. Cannot backup without the partition mounted."
            exit 1
        fi
    else
        exit 1
    fi
fi

# Ensure snapshot directory exists
mkdir -p "$BACKUP_ROOT"
mkdir -p "$(dirname "$INDEX_LAST")"

# 2. Build current file index (tracks paths, sizes, and mtimes)
# This prevents missing deletions/replacements where the total weight remains the same.
echo "[*] Analyzing current live system state (indexing files)..."
sudo find "$OVERLAY_DIR" -xdev -printf "%p|%s|%T@\n" 2>/dev/null | LC_ALL=C sort > "$INDEX_CURR"

# 3. Detect changes
HAS_CHANGES=true
if [ -f "$INDEX_LAST" ]; then
    if cmp -s "$INDEX_CURR" "$INDEX_LAST"; then
        HAS_CHANGES=false
    fi
fi

if [ "$HAS_CHANGES" = false ]; then
    echo "[+] No changes detected in the live system overlay since the last snapshot."
    exit 0
fi

# Print changes breakdown
if [ -f "$INDEX_LAST" ]; then
    ADDITIONS=$(LC_ALL=C comm -13 "$INDEX_LAST" "$INDEX_CURR" | wc -l)
    DELETIONS=$(LC_ALL=C comm -23 "$INDEX_LAST" "$INDEX_CURR" | wc -l)
    echo "[*] Changes detected:"
    echo "    - Added/Modified files: $ADDITIONS"
    echo "    - Deleted files: $DELETIONS"
else
    TOTAL_FILES=$(wc -l < "$INDEX_CURR")
    echo "[*] No previous index found. First-time snapshot will copy $TOTAL_FILES files."
fi

# 4. User confirmation (if interactive)
if [ "$AUTO_MODE" = false ]; then
    read -r -p "[?] Would you like to create an incremental snapshot now? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "[*] Snapshot cancelled by user."
        exit 0
    fi
fi

# 5. Perform space-efficient hard-linked rsync snapshot
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NEW_SNAP="$BACKUP_ROOT/backup_$TIMESTAMP"
LATEST_LINK="$BACKUP_ROOT/latest"

echo "[*] Creating incremental snapshot at: $NEW_SNAP"

RSYNC_OPTS="-aH --info=stats2"
# If a previous snapshot exists, use it to hard-link unmodified files
if [ -L "$LATEST_LINK" ] && [ -d "$(readlink -f "$LATEST_LINK")" ]; then
    PREV_SNAP_PATH=$(readlink -f "$LATEST_LINK")
    echo "[*] Unchanged files will be hardlinked to: $PREV_SNAP_PATH"
    RSYNC_OPTS="$RSYNC_OPTS --link-dest=$PREV_SNAP_PATH"
fi

# Run the backup
mkdir -p "$NEW_SNAP"
sudo rsync $RSYNC_OPTS "$OVERLAY_DIR/" "$NEW_SNAP/"

# Update the 'latest' symlink atomically
rm -f "$LATEST_LINK"
ln -s "$NEW_SNAP" "$LATEST_LINK"

# Save the current state index as last index
cp "$INDEX_CURR" "$INDEX_LAST"

# Send desktop notification
if command -v notify-send >/dev/null 2>&1; then
    ADDITIONS=${ADDITIONS:-${TOTAL_FILES:-0}}
    DELETIONS=${DELETIONS:-0}
    if [ -f "$INDEX_LAST" ] && [ "${DELETIONS}" -ne 0 -o "${ADDITIONS}" -ne 0 ]; then
        notify-send -u normal -i document-save "Live System Snapshot" "Saved incremental snapshot: backup_$TIMESTAMP ($ADDITIONS changed, $DELETIONS deleted)"
    else
        notify-send -u normal -i document-save "Live System Snapshot" "Saved first full snapshot: backup_$TIMESTAMP"
    fi
fi

echo "[+] Snapshot created and verified successfully."
