#!/usr/bin/env bash
# live-architect.sh
# Builds the monolithic VelocityOS-ConVigurator.iso from the live OverlayFS state.

set -euo pipefail

# --- Term Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Configuration ---
TEMP_DIR="/mnt/temp"
STAGING_DIR="${TEMP_DIR}/iso_staging"
OFFLOAD_DIR="${TEMP_DIR}/overlay_offload"
BACKUP_DIR="${TEMP_DIR}/iso_backups"
NEW_ISO_NAME="VelocityOS-ConVigurator.iso"
TARGET_ISO_PATH=""
MODE=""

# Heavy directories to offload to /mnt/temp in DEV mode
DEV_DIRS=(
    "/var/cache/pacman/pkg"
    "/home/garuda/.cache"
    "/home/garuda/.npm"
    "/home/garuda/.cargo"
)
LOG_DIR="/var/log"

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev) MODE="dev"; shift ;;
        --prod) MODE="prod"; shift ;;
        --iso) TARGET_ISO_PATH="$2"; shift 2 ;;
        *) echo -e "${RED}[!] Unknown argument: $1${NC}"; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo -e "${RED}[!] Please specify --dev or --prod${NC}"
    exit 1
fi

if [[ -z "$TARGET_ISO_PATH" || ! -f "$TARGET_ISO_PATH" ]]; then
    echo -e "${RED}[!] Please provide a valid path to the old ISO using --iso (e.g., --iso \"/mnt/usb/old.iso\")${NC}"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[!] Please run as root (sudo).${NC}"
    exit 1
fi

if ! mountpoint -q "$TEMP_DIR"; then
    echo -e "${RED}[!] $TEMP_DIR is not mounted. Mount your 0.5TB drive there first.${NC}"
    exit 1
fi

echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}   VelocityOS ConVigurator - Live ISO Architect      ${NC}"
echo -e "${CYAN}=====================================================${NC}"

# --- Phase 1: Environment Bind Mounting ---
echo -e "\n${GREEN}[*] Phase 1: Configuring Environment ($MODE mode)...${NC}"
mkdir -p "$OFFLOAD_DIR"

bind_offload() {
    local src_dir="$1"
    local dest_dir="${OFFLOAD_DIR}${src_dir}"
    
    if [[ ! -d "$src_dir" ]]; then
        mkdir -p "$src_dir"
    fi

    # Only bind mount if not already mounted
    if ! mountpoint -q "$src_dir"; then
        echo -e "    -> Offloading $src_dir to $TEMP_DIR"
        mkdir -p "$dest_dir"
        # Sync existing data over to the hard drive before binding
        rsync -a "$src_dir/" "$dest_dir/"
        mount --bind "$dest_dir" "$src_dir"
    else
        echo -e "    -> $src_dir is already offloaded."
    fi
}

if [[ "$MODE" == "dev" ]]; then
    for dir in "${DEV_DIRS[@]}"; do
        bind_offload "$dir"
    done
fi

# Always offload logs to prevent RAM bloat
bind_offload "$LOG_DIR"

# --- Phase 2: Initramfs Generation ---
echo -e "\n${GREEN}[*] Phase 2: Updating Initramfs and Kernel Modules...${NC}"
if command -v dracut-rebuild &>/dev/null; then
    dracut-rebuild || { echo -e "${RED}[!] dracut-rebuild failed.${NC}"; exit 1; }
elif command -v mkinitcpio &>/dev/null; then
    mkinitcpio -P || { echo -e "${RED}[!] mkinitcpio failed.${NC}"; exit 1; }
elif command -v dracut &>/dev/null; then
    dracut --regenerate-all --force || { echo -e "${RED}[!] dracut failed.${NC}"; exit 1; }
else
    echo -e "${YELLOW}[!] Warning: Neither dracut-rebuild, mkinitcpio, nor dracut was found. Skipping initramfs generation.${NC}"
fi


# --- Phase 3: Staging the ISO ---
echo -e "\n${GREEN}[*] Phase 3: Extracting Old ISO to Staging Area...${NC}"
mkdir -p "$STAGING_DIR"
TMP_MOUNT="/mnt/old_iso_mount"
mkdir -p "$TMP_MOUNT"

if ! mountpoint -q "$TMP_MOUNT"; then
    mount -o loop,ro "$TARGET_ISO_PATH" "$TMP_MOUNT"
fi

# Sync ISO contents to writable staging area on the temp drive
echo -e "    -> Syncing contents (this may take a moment)..."
rsync -a --delete "$TMP_MOUNT/" "$STAGING_DIR/"
umount "$TMP_MOUNT"
rm -rf "$TMP_MOUNT"

# --- Phase 4: Syncing Boot Kernels ---
echo -e "\n${GREEN}[*] Phase 4: Syncing active vmlinuz/initramfs to ISO boot sector...${NC}"
# Garuda typically stores these inside the ISO under arch/boot or garuda/boot
ISO_BOOT_DIR=$(find "$STAGING_DIR" -type d -name "boot" -path "*/x86_64/*" | head -n 1)

if [[ -n "$ISO_BOOT_DIR" ]]; then
    echo -e "    -> Found ISO boot directory at $ISO_BOOT_DIR"
    cp -f /boot/vmlinuz-linux* "$ISO_BOOT_DIR/" 2>/dev/null || true
    cp -f /boot/initramfs-linux* "$ISO_BOOT_DIR/" 2>/dev/null || true
else
    echo -e "${YELLOW}    [!] Could not locate nested boot directory. Relying on existing ISO kernel.${NC}"
fi

# --- Phase 5: Monolithic Squash ---
echo -e "\n${GREEN}[*] Phase 5: Squashing active system into monolithic rootfs.sfs...${NC}"
# Find where the rootfs.sfs belongs in the staging dir
ROOTFS_TARGET=$(find "$STAGING_DIR" -type f -name "rootfs.sfs" | head -n 1)

if [[ -z "$ROOTFS_TARGET" ]]; then
    echo -e "${RED}[!] Could not find rootfs.sfs in the extracted ISO structure to overwrite.${NC}"
    exit 1
fi

echo -e "    -> Target: $ROOTFS_TARGET"
# Remove old fragmented layers to save space and rely on the new monolithic one
find "$(dirname "$ROOTFS_TARGET")" -type f -name "*.sfs" ! -name "rootfs.sfs" -exec rm -f {} +
rm -f "$ROOTFS_TARGET"

TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_LIMIT_MB=$(( TOTAL_MEM_KB / 4 / 1024 ))

echo -e "    -> Running mksquashfs (Memory limited to ${MEM_LIMIT_MB}M to prevent OOM)..."
mksquashfs / "$ROOTFS_TARGET" \
    -comp zstd -b 1M -noappend -mem "${MEM_LIMIT_MB}M" \
    -e /proc /sys /dev /run /tmp /mnt /media

# --- Phase 6: Repack ISO ---
echo -e "\n${GREEN}[*] Phase 6: Repacking ISO ($NEW_ISO_NAME)...${NC}"
NEW_ISO_FULL_PATH="${TEMP_DIR}/${NEW_ISO_NAME}"

# We dynamically locate the efiboot.img because case sensitivity matters
EFI_IMG=$(find "$STAGING_DIR" -type f -path "*/efi*.img" | head -n 1)
if [[ -n "$EFI_IMG" ]]; then
    EFI_REL_PATH="${EFI_IMG#$STAGING_DIR/}"
    EFI_FLAG="-e $EFI_REL_PATH -no-emul-boot -isohybrid-gpt-basdat"
else
    EFI_FLAG=""
    echo -e "${YELLOW}    [!] EFI boot image not found, skipping EFI boot flags.${NC}"
fi

# We build the ISO. Ventoy primarily relies on the ISO9660 structure and EFI files.
xorriso -as mkisofs -iso-level 3 \
    -full-iso9660-filenames -volid "VELOCITY_OS" \
    $EFI_FLAG \
    -output "$NEW_ISO_FULL_PATH" "$STAGING_DIR"

# --- Phase 7: Auto-Swap ---
echo -e "\n${GREEN}[*] Phase 7: Swapping old ISO on flash drive...${NC}"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OLD_ISO_NAME=$(basename "$TARGET_ISO_PATH")
USB_DIR=$(dirname "$TARGET_ISO_PATH")

echo -e "    -> Backing up old ISO to $BACKUP_DIR/${OLD_ISO_NAME}_${TIMESTAMP}.bak"
mv "$TARGET_ISO_PATH" "$BACKUP_DIR/${OLD_ISO_NAME}_${TIMESTAMP}.bak"

echo -e "    -> Moving $NEW_ISO_NAME to Ventoy drive ($USB_DIR)..."
mv "$NEW_ISO_FULL_PATH" "$USB_DIR/$NEW_ISO_NAME"

echo -e "\n${CYAN}[+] SUCCESS: VelocityOS Architect has completed the build.${NC}"
echo -e "    You can safely reboot. The new system is ready on your Ventoy drive."