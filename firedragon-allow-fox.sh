#!/usr/bin/env bash
# firedragonAllowFoxSettingsServer.sh
# Safely configures Firedragon to enable Firefox Translations and Remote Settings.

set -euo pipefail

CFG_FILE="/usr/lib/firedragon/firedragon.cfg"
BACKUP_FILE="${CFG_FILE}.bak.$(date +%Y%m%d%H%M%S)"

# 1. Sanity Check: Ensure Firedragon is not running
if pgrep -x "firedragon" > /dev/null; then
    echo "[-] WARNING: Firedragon is currently running."
    echo "    Modifying preferences while the browser is open can cause changes to be overwritten on exit."
    read -r -p "    Do you want to continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "[*] Aborted. Please close Firedragon and rerun the script."
        exit 1
    fi
fi

# 2. Verify Config File Existence
if [ ! -f "$CFG_FILE" ]; then
    echo "[!] Error: Firedragon configuration file not found at $CFG_FILE."
    echo "    Please verify your installation path."
    exit 1
fi

# Determine if we need sudo privilege escalation
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
    echo "[*] Script requires root privileges to modify system files. Sudo prompt may appear."
fi

# 3. Create a Backup of the Original Config
echo "[*] Creating backup of global configuration..."
$SUDO cp "$CFG_FILE" "$BACKUP_FILE"
echo "    Backup saved to: $BACKUP_FILE"

# 4. Helper Function to Update or Append Preferences cleanly
# Arguments: pref_name, pref_val, is_string
update_pref() {
    local pref_name="$1"
    local pref_val="$2"
    local is_string="$3"
    
    local formatted_val
    if [ "$is_string" = "true" ]; then
        formatted_val="\"$pref_val\""
    else
        formatted_val="$pref_val"
    fi

    echo "[*] Configuring '$pref_name' -> $formatted_val"

    # Check if the preference exists in the config (commented or not)
    if grep -qE "^\s*(//\s*)?defaultPref\(\s*\"$pref_name\"" "$CFG_FILE"; then
        # Replace the existing line and ensure it is uncommented
        $SUDO sed -i -E "s|^\s*(//\s*)?defaultPref\(\s*\"$pref_name\".*|defaultPref(\"$pref_name\", $formatted_val);|g" "$CFG_FILE"
    else
        # If the preference does not exist, insert it neatly right before loadConfig()
        if grep -q "loadConfig(" "$CFG_FILE"; then
            $SUDO sed -i "/loadConfig(/i defaultPref(\"$pref_name\", $formatted_val);" "$CFG_FILE"
        else
            # Fallback append to the end of the file
            echo "defaultPref(\"$pref_name\", $formatted_val);" | $SUDO tee -a "$CFG_FILE" > /dev/null
        fi
    fi
}

# 5. Apply Core Configuration Changes
# Point Remote Settings to Mozilla's production endpoint
update_pref "services.settings.server" "https://firefox.settings.services.mozilla.com/v1" "true"

# Ensure Remote Settings engine is active globally
update_pref "services.settings.enabled" "true" "false"

# Enable local Firefox translation engine 
update_pref "browser.translations.enable" "true" "false"

# Enable Firedragon specific translations switch
update_pref "firedragon.translations.enable" "true" "false"

# Configure the secure Mozilla translations CDN path
update_pref "browser.translations.cdnPath" "https://translations-cdn.prod.mozaws.net" "true"

# 6. Scan and Fix Profile-Level Overrides (prefs.js)
echo -e "\n[*] Scanning local user profiles for overriding preferences..."
PROFILE_DIRS=("$HOME/.firedragon" "$HOME/.mozilla/firedragon")
found_overrides=false

for dir in "${PROFILE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        # Find all active profile prefs.js files
        find "$dir" -name "prefs.js" | while read -r prefs_file; do
            echo "    Checking profile: $prefs_file"
            
            # Identify any overrides that would bypass system configurations
            for pref in "services.settings.server" "services.settings.enabled" "browser.translations.enable" "firedragon.translations.enable" "browser.translations.cdnPath"; do
                if grep -q "user_pref(\"$pref\"" "$prefs_file"; then
                    found_overrides=true
                    echo "    [!] Found profile override for '$pref' in $prefs_file"
                    # Create a backup of the profile prefs.js
                    cp "$prefs_file" "${prefs_file}.bak"
                    # Strip the overriding user_pref line so it inherits our clean global default
                    sed -i "/user_pref(\"$pref\"/d" "$prefs_file"
                    echo "        -> Cleared override (original backed up to ${prefs_file}.bak)."
                fi
            done
        done
    fi
done

if [ "$found_overrides" = "false" ]; then
    echo "    No conflicting profile-level overrides found. Local profiles will inherit global settings."
fi

echo -e "\n[+] Success! Firedragon translations have been successfully enabled and configured."
echo "    Please launch Firedragon to test your translation models."
