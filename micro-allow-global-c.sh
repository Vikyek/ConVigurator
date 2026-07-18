#!/usr/bin/env bash

# Global skeleton file path
SKEL_FILE="/etc/skel/.config/micro/settings.json"

# Check if skel file exists
if [ ! -f "$SKEL_FILE" ]; then
    echo "Micro skeleton configuration file not found at $SKEL_FILE."
else
    echo "Found skeleton file: $SKEL_FILE"
    
    # Check current clipboard setting
    curr_setting=$(jq -r '.clipboard' "$SKEL_FILE" 2>/dev/null || true)
    
    if [ "$curr_setting" = "null" ] || [ -z "$curr_setting" ]; then
        echo "Status: Clipboard setting is not defined in skeleton (defaults to external)."
    elif [ "$curr_setting" = "external" ]; then
        echo "Status: Clipboard is already set to external (global)."
    else
        echo "Status: WARNING! Clipboard is set to a custom value: '$curr_setting'."
    fi
    
    # Update skeleton settings to set clipboard to external
    if [ "$EUID" -ne 0 ]; then
        echo "Running with sudo to modify skeleton file..."
        sudo jq '. + {"clipboard": "external"}' "$SKEL_FILE" > /tmp/micro_skel.json
        sudo mv /tmp/micro_skel.json "$SKEL_FILE"
    else
        jq '. + {"clipboard": "external"}' "$SKEL_FILE" > /tmp/micro_skel.json
        mv /tmp/micro_skel.json "$SKEL_FILE"
    fi
    
    # Verify success
    new_setting=$(jq -r '.clipboard' "$SKEL_FILE" 2>/dev/null || true)
    if [ "$new_setting" = "external" ]; then
        echo "Success: Skeleton configuration updated to always use global clipboard."
    else
        echo "Failure: Could not update skeleton configuration."
    fi
fi

# Now update settings for all existing users' home directories
echo "Updating settings for existing users..."
for user_dir in /home/*; do
    if [ -d "$user_dir" ]; then
        user_file="$user_dir/.config/micro/settings.json"
        if [ -f "$user_file" ]; then
            echo "Found user settings file: $user_file"
            curr_setting=$(jq -r '.clipboard' "$user_file" 2>/dev/null || true)
            
            if [ "$curr_setting" = "external" ]; then
                echo "Status: User clipboard is already set to external (global)."
                continue
            fi
            
            if [ "$EUID" -ne 0 ]; then
                sudo jq '. + {"clipboard": "external"}' "$user_file" > /tmp/micro_user.json
                sudo mv /tmp/micro_user.json "$user_file"
                # Keep file ownership
                user_name=$(basename "$user_dir")
                sudo chown "$user_name":"$user_name" "$user_file"
            else
                jq '. + {"clipboard": "external"}' "$user_file" > /tmp/micro_user.json
                mv /tmp/micro_user.json "$user_file"
                user_name=$(basename "$user_dir")
                chown "$user_name":"$user_name" "$user_file"
            fi
            
            # Verify
            new_setting=$(jq -r '.clipboard' "$user_file" 2>/dev/null || true)
            if [ "$new_setting" = "external" ]; then
                echo "Success: Updated $user_file to always use global clipboard."
            else
                echo "Failure: Could not update $user_file."
            fi
        fi
    fi
done
