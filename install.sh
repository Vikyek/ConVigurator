#!/usr/bin/env bash
# install.sh
# Installer for the ConVigurator script collection (currently: conv-alias).
set -euo pipefail

# Resolve the calling user's actual home directory even under sudo execution
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Change directory to the script's actual directory to support execution from other folders
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SHELL_CONFIGS=()
[ -f "$REAL_HOME/.bashrc" ] && SHELL_CONFIGS+=("$REAL_HOME/.bashrc")
[ -f "$REAL_HOME/.zshrc" ] && SHELL_CONFIGS+=("$REAL_HOME/.zshrc")
FISH_CONFIG="$REAL_HOME/.config/fish/config.fish"

AUTO_RUN=false
for arg in "$@"; do
    case "$arg" in
        -r|--run|--execute)
            AUTO_RUN=true
            ;;
    esac
done

echo "=========================================="
echo "    ConVigurator Installer Sequence"
echo "=========================================="

# --- STAGE 0: DEPENDENCY SETUP ---
echo -e "\n[*] Ensuring dependency: power-profile-switcher..."
POWER_SWITCHER_DIR="/home/garuda/Projects/power-profile-switcher"
if [ -d "$POWER_SWITCHER_DIR" ]; then
    if [ -f "$POWER_SWITCHER_DIR/install.sh" ]; then
        echo "    [+] Executing installer for power-profile-switcher..."
        # Execute the installer under the real calling user context to target correct user config paths
        su - "$REAL_USER" -c "bash $POWER_SWITCHER_DIR/install.sh"
    fi
else
    echo "    [!] Warning: power-profile-switcher directory not found at $POWER_SWITCHER_DIR."
fi

echo -e "\n[*] Ensuring dependency: omarchy-ai-usage..."
OMARCHY_DIR="/home/garuda/Projects/omarchy-ai-usage"
if [ -d "$OMARCHY_DIR" ]; then
    if [ -f "$OMARCHY_DIR/install.sh" ]; then
        echo "    [+] Executing installer for omarchy-ai-usage..."
        su - "$REAL_USER" -c "bash $OMARCHY_DIR/install.sh"
    fi
else
    echo "    [!] Warning: omarchy-ai-usage directory not found at $OMARCHY_DIR."
fi

# --- STAGE 1: CLEAN UP OLD AND NON-COMPLIANT INSTANCES ---
echo -e "\n[*] Auditing system for old/non-compliant instances..."

OLD_BINARIES=(
    "/usr/local/bin/conv-alias-manager.sh"
    "/usr/local/bin/conv-alias-manager"
    "/usr/local/bin/conv-alias.sh"
)

DE_ALIAS_NAMES=(
    "conv-alias-manager"
)

# 1. Clean up old binaries
for bin in "${OLD_BINARIES[@]}"; do
    if [ -f "$bin" ]; then
        echo "    [!] Found old binary: $bin"
        if [ -w "$(dirname "$bin")" ]; then
            rm -f "$bin"
            echo "    [+] Removed $bin"
        else
            echo "    [*] Requesting admin privileges to remove $bin..."
            sudo rm -f "$bin"
            echo "    [+] Removed $bin"
        fi
    fi
done

# 2. De-alias old aliases from config files
for rc in "${SHELL_CONFIGS[@]}"; do
    if [ -f "$rc" ]; then
        for alias_name in "${DE_ALIAS_NAMES[@]}"; do
            if grep -Fq "alias $alias_name=" "$rc"; then
                echo "    [!] Found old alias '$alias_name' in $(basename "$rc")"
                sed -i "/alias $alias_name=/d" "$rc"
                echo "    [+] De-aliased '$alias_name' from $(basename "$rc")"
            fi
        done
    fi
done

if [ -f "$FISH_CONFIG" ]; then
    for alias_name in "${DE_ALIAS_NAMES[@]}"; do
        if grep -Fq "alias $alias_name " "$FISH_CONFIG"; then
            echo "    [!] Found old alias '$alias_name' in config.fish"
            sed -i "/alias $alias_name /d" "$FISH_CONFIG"
            echo "    [+] De-aliased '$alias_name' from config.fish"
        fi
    done
fi

# --- STAGE 2: INSTALL NEW CONV-ALIAS SCRIPT ---
echo -e "\n[*] Installing conv-alias script..."

SOURCE_SCRIPT="conv-alias.sh"
DEST_BINARY="/usr/local/bin/conv-alias"

if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "[!] Error: Source file '$SOURCE_SCRIPT' not found in current directory." >&2
    exit 1
fi

# Copy script to /usr/local/bin/conv-alias
echo "    Copying '$SOURCE_SCRIPT' to '$DEST_BINARY'..."
if [ -w "$(dirname "$DEST_BINARY")" ]; then
    cp "$SOURCE_SCRIPT" "$DEST_BINARY"
    chmod +x "$DEST_BINARY"
else
    echo "    [*] Requesting admin privileges to write to /usr/local/bin..."
    sudo cp "$SOURCE_SCRIPT" "$DEST_BINARY"
    sudo chmod +x "$DEST_BINARY"
fi
echo "    [+] Successfully installed to $DEST_BINARY"

# --- STAGE 3: SELF-ALIAS REGISTRATION ---
echo -e "\n[*] Registering global 'conv-alias' command..."
# Run the newly installed script with -s to register it
"$DEST_BINARY" -s

# --- STAGE 3.5: INSTALL BOOT TUNING SERVICE ---
echo -e "\n[*] Installing ConVigurator Boot Tuning Service..."
SERVICE_FILE="conv-boot.service"
TARGET_SERVICE="/etc/systemd/system/conv-boot.service"
if [ -f "$SERVICE_FILE" ]; then
    echo "    Copying '$SERVICE_FILE' to '$TARGET_SERVICE'..."
    sudo cp "$SERVICE_FILE" "$TARGET_SERVICE"
    echo "    Reloading systemd and enabling conv-boot.service..."
    sudo systemctl daemon-reload
    sudo systemctl enable conv-boot.service
    echo "    [+] ConVigurator Boot Tuning Service installed and enabled."
else
    echo "    [!] Warning: '$SERVICE_FILE' not found, skipping service installation."
fi

# --- STAGE 4: EXECUTION BLOCK ---
run_alias_tool() {
    echo -e "\n[*] Running conv-alias on ConVigurator directory..."
    "$DEST_BINARY" "$(dirname "$(readlink -f "$0")")"
}

if [ "$AUTO_RUN" = true ]; then
    run_alias_tool
else
    echo ""
    read -r -p "[?] Would you like to run the alias manager on ConVigurator now? (y/N): " run_confirm
    if [[ "$run_confirm" =~ ^[Yy]$ ]]; then
        run_alias_tool
    else
        echo "    [*] Skipped execution. (Hint: Use -r, --run, or --execute flags to run immediately in the future)."
    fi
fi

# --- STAGE 5: ACTIVATE SHELL ---
echo ""
read -r -p "[?] Would you like to spawn a new subshell now to start using 'conv-alias' immediately? (y/N): " shell_confirm
if [[ "$shell_confirm" =~ ^[Yy]$ ]]; then
    echo "[*] Launching new $SHELL subshell..."
    exec "$SHELL"
fi

echo -e "\n[+] Installation complete! Please source your shell profile or open a new terminal to start using 'conv-alias'."
