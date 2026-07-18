#!/usr/bin/env bash
# conv-alias.sh
# Standardizes script filenames, enforces "conv-" alias conventions,
# guards against native command shadowing, and audits profiles.
set -euo pipefail

# Resolve the calling user's actual home directory even under sudo execution
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Default Configuration
TARGET_DIR=""
DRY_RUN=false
RENAME_MODE="default" # Options: default, rename-only, alias-only, no-rename
SKIP_SCAN=false
SCAN_ONLY=false
AUTO_ACCEPT=false
SELF_ALIAS=false

SHELL_CONFIGS=()
[ -f "$REAL_HOME/.bashrc" ] && SHELL_CONFIGS+=("$REAL_HOME/.bashrc")
[ -f "$REAL_HOME/.zshrc" ] && SHELL_CONFIGS+=("$REAL_HOME/.zshrc")
FISH_CONFIG="$REAL_HOME/.config/fish/config.fish"

show_help() {
    echo "Usage: $0 [options] [target_directory]"
    echo "Options:"
    echo "  -s, --self-alias   Register this script itself as a global 'conv-alias' alias"
    echo "  -d, --dry-run      Simulate operations without making any changes"
    echo "  -r, --rename-only  Only normalize filenames; do not generate aliases"
    echo "  -a, --alias-only   Generate normalized aliases but skip renaming files"
    echo "  -n, --no-rename    Do not rename files or split their aliases; pair them raw"
    echo "  -k, --skip-scan    Skip the pre-scan validation of existing profile aliases"
    echo "  -o, --scan-only    Only run the pre-scan validation on active profiles, then exit"
    echo "  -y, --auto-accept  Auto-convert non-compliant profile aliases without prompting"
    echo "  -h, --help         Show this help breakdown"
    exit 0
}

# Parse Command-Line Flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--self-alias)  SELF_ALIAS=true; shift ;;
        -d|--dry-run)     DRY_RUN=true; shift ;;
        -r|--rename-only) RENAME_MODE="rename-only"; shift ;;
        -a|--alias-only)  RENAME_MODE="alias-only"; shift ;;
        -n|--no-rename)   RENAME_MODE="no-rename"; shift ;;
        -k|--skip-scan)   SKIP_SCAN=true; shift ;;
        -o|--scan-only)   SCAN_ONLY=true; shift ;;
        -y|--auto-accept) AUTO_ACCEPT=true; shift ;;
        -h|--help)        show_help ;;
        -*) echo "[!] Error: Unknown option '$1'" >&2; exit 1 ;;
        *)  TARGET_DIR="$1"; shift ;;
    esac
done

# Helper: Transform CamelCase/PascalCase/Underscores to clean dashed-lowercase
transform_name() {
    local input="$1"
    local processed
    processed=$(echo "$input" | sed -E 's/([A-Z])/-\1/g' | tr '_' '-' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    processed=$(echo "$processed" | sed -E 's/-+/-/g' | sed -E 's/^-//; s/-$//')
    if [ ${#processed} -gt 20 ]; then
        processed="${processed:0:20}"
        processed=$(echo "$processed" | sed -E 's/-$//')
    fi
    echo "$processed"
}

# --- SELF-ALIAS SEQUENCE ---
if [ "$SELF_ALIAS" = true ]; then
    SELF_PATH=$(readlink -f "$0")
    SELF_BASE=$(basename "$SELF_PATH")
    raw_name="${SELF_BASE%.*}"
    raw_name="${raw_name%.sh}"
    raw_name="${raw_name#conv-}"
    SELF_ALIAS_NAME="conv-$(transform_name "$raw_name")"

    echo "[*] Initiating self-aliasing registration for '$SELF_ALIAS_NAME'..."
    echo "    Source binary path: $SELF_PATH"

    # Anti-Shadowing Check
    if command -v "$SELF_ALIAS_NAME" >/dev/null 2>&1 || type "$SELF_ALIAS_NAME" >/dev/null 2>&1; then
        # If it's already an alias pointing to the same target, that's fine. Otherwise warning.
        if ! alias "$SELF_ALIAS_NAME" 2>/dev/null | grep -Fq "$SELF_PATH" && ! type "$SELF_ALIAS_NAME" 2>/dev/null | grep -Fq "alias"; then
            echo "[!] Error: Core command collision. '$SELF_ALIAS_NAME' is already reserved by the shell architecture." >&2
            exit 1
        fi
    fi

    # Write to POSIX Profile Configurations
    for rc in "${SHELL_CONFIGS[@]}"; do
        if grep -Fq "alias $SELF_ALIAS_NAME=" "$rc"; then
            echo "    -> Self-alias linkage already verified in $(basename "$rc")"
        else
            if [ "$DRY_RUN" = true ]; then
                echo "    [Dry-Run] Would append: alias $SELF_ALIAS_NAME='$SELF_PATH' to $(basename "$rc")"
            else
                echo "alias $SELF_ALIAS_NAME='$SELF_PATH'" >> "$rc"
                echo "    [+] Registered shortcut link within $(basename "$rc")"
            fi
        fi
    done

    # Write to Fish Configuration
    if [ -d "$(dirname "$FISH_CONFIG")" ] || [ -f "$FISH_CONFIG" ]; then
        if [ -f "$FISH_CONFIG" ] && grep -Fq "alias $SELF_ALIAS_NAME " "$FISH_CONFIG"; then
            echo "    -> Self-alias linkage already verified in config.fish"
        else
            if [ "$DRY_RUN" = true ]; then
                echo "    [Dry-Run] Would append: alias $SELF_ALIAS_NAME '$SELF_PATH' to config.fish"
            else
                mkdir -p "$(dirname "$FISH_CONFIG")"
                echo "alias $SELF_ALIAS_NAME '$SELF_PATH'" >> "$FISH_CONFIG"
                echo "    [+] Registered shortcut link within config.fish"
            fi
        fi
    fi

    echo "[+] Self-aliasing sequence completed. Source profiles or cycle terminals to finalize application."
    exit 0
fi

# Resolve Target Directory (Fallback to current script folder location if blank)
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(dirname "$(readlink -f "$0")")"
fi

# Mutually Exclusive Flag Validations
if [ "$SCAN_ONLY" = true ] && [ "$SKIP_SCAN" = true ]; then
    echo "[!] Error: --scan-only and --skip-scan cannot be used together." >&2
    exit 1
fi
if [[ "$RENAME_MODE" != "default" && "$SCAN_ONLY" = true ]]; then
    echo "[!] Error: File operations cannot be mixed with --scan-only mode." >&2
    exit 1
fi

# --- STAGE 1: PROFILE PRE-SCAN AUDIT ---
audit_profile_aliases() {
    echo "[*] Initializing pre-scan audit on active shell profiles..."
    local non_compliant_found=false

    local profiles=("${SHELL_CONFIGS[@]}")
    [ -f "$FISH_CONFIG" ] && profiles+=("$FISH_CONFIG")

    for profile in "${profiles[@]}"; do
        [ ! -f "$profile" ] && continue
        local p_name=$(basename "$profile")
        
        while IFS= read -r line; do
            local current_alias=""
            if [[ "$p_name" == *"fish"* ]]; then
                current_alias=$(echo "$line" | sed -E -n 's/^alias ([a-zA-Z0-9_-]+) .*/\1/p')
            else
                current_alias=$(echo "$line" | sed -E -n 's/^alias ([a-zA-Z0-9_-]+)=.*/\1/p')
            fi
            
            [ -z "$current_alias" ] && continue
            
            # Skip checking our own tool alias
            if [ "$current_alias" = "conv-alias" ] || [ "$current_alias" = "conv-alias-manager" ]; then
                continue
            fi
            
            if [[ ! "$current_alias" =~ ^conv-[a-z0-9-]+$ ]]; then
                non_compliant_found=true
                local clean_base=$(transform_name "$current_alias")
                local target_alias="conv-$clean_base"
                echo "[!] Non-compliant alias detected in $p_name: '$current_alias'"
                echo "    Suggested correction: '$target_alias'"

                local choice="n"
                if [ "$AUTO_ACCEPT" = true ]; then
                    choice="y"
                elif [ "$DRY_RUN" = false ]; then
                    read -r -p "[?] Convert this alias definition? (y/N): " choice
                fi

                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    if [ "$DRY_RUN" = true ]; then
                        echo "    [Dry-Run] Would modify line in $p_name to target '$target_alias'"
                    else
                        if [[ "$p_name" == *"fish"* ]]; then
                            sed -i "s/^alias $current_alias /alias $target_alias /g" "$profile"
                        else
                            sed -i "s/^alias $current_alias=/alias $target_alias=/g" "$profile"
                        fi
                        echo "    [+] Successfully updated alias in $p_name."
                    fi
                fi
            fi
        done < <(grep -E '^alias [a-zA-Z0-9_-]+' "$profile" || true)
    done

    if [ "$non_compliant_found" = false ]; then
        echo "[+] Shell profiles checked. 100% compliant with standard naming rules."
    fi
}

if [ "$SKIP_SCAN" = false ]; then
    audit_profile_aliases
    if [ "$SCAN_ONLY" = true ]; then
        echo "[+] Scan-only run completed successfully."
        exit 0
    fi
fi

# --- STAGE 2: DIRECTORY FILENAME AND ALIAS ALIGNMENT ---
echo -e "\n[*] Processing targeted directory..."
if [ ! -d "$TARGET_DIR" ]; then
    echo "[!] Error: Target directory '$TARGET_DIR' does not exist." >&2
    exit 1
fi

VALID_EXTS=("sh" "bash" "fish" "py" "pl" "rb")
found_files=false

while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    ext="${filename##*.}"
    base_name="${filename%.*}"
    
    valid_ext=false
    for e in "${VALID_EXTS[@]}"; do
        if [ "$ext" = "$e" ]; then valid_ext=true; break; fi
    done
    [ "$valid_ext" = false ] && continue
    found_files=true

    final_base="$base_name"
    working_filepath="$file"

    if [ "$RENAME_MODE" != "no-rename" ]; then
        final_base=$(transform_name "$base_name")
        final_filename="${final_base}.${ext}"
        
        if [ "$base_name" != "$final_base" ] && [ "$RENAME_MODE" != "alias-only" ]; then
            working_filepath="${TARGET_DIR}/${final_filename}"
            echo "[*] File normalization triggered: '$filename' -> '$final_filename'"
            
            if [ -f "$working_filepath" ]; then
                echo "    [!] Warning: Skipping rename. Destination file '$final_filename' already exists."
                working_filepath="$file"
                final_base="$base_name"
            elif [ "$DRY_RUN" = true ]; then
                echo "    [Dry-Run] Would rename file to '$final_filename'"
            else
                mv "$file" "$working_filepath"
                echo "    [+] File name updated successfully on system disk."
            fi
        fi
    fi

    [ "$RENAME_MODE" = "rename-only" ] && continue

    alias_base="${final_base#conv-}"
    target_alias="conv-$alias_base"
    
    if command -v "$target_alias" >/dev/null 2>&1 || type "$target_alias" >/dev/null 2>&1; then
        # Check if the command is just our registered alias to prevent self-conflict
        if ! alias "$target_alias" 2>/dev/null | grep -Fq "$working_filepath" && ! type "$target_alias" 2>/dev/null | grep -Fq "alias"; then
            echo "    [!] CRITICAL CONFLICT: Target alias '$target_alias' shadows a system binary or keyword. Bypassing registration."
            continue
        fi
    fi

    echo "[*] Processing system shell linkage for alias: '$target_alias'"

    for rc in "${SHELL_CONFIGS[@]}"; do
        if grep -Fq "alias $target_alias=" "$rc"; then
            echo "    -> Link already exists in $(basename "$rc")"
        else
            if [ "$DRY_RUN" = true ]; then
                echo "    [Dry-Run] Would append: alias $target_alias='sudo $working_filepath' to $(basename "$rc")"
            else
                echo "alias $target_alias='sudo $working_filepath'" >> "$rc"
                echo "    [+] Appended alias link to $(basename "$rc")"
            fi
        fi
    done

    if [ -d "$(dirname "$FISH_CONFIG")" ]; then
        if [ -f "$FISH_CONFIG" ] && grep -Fq "alias $target_alias " "$FISH_CONFIG"; then
            echo "    -> Link already exists in config.fish"
        else
            if [ "$DRY_RUN" = true ]; then
                echo "    [Dry-Run] Would append: alias $target_alias 'sudo $working_filepath' to config.fish"
            else
                mkdir -p "$(dirname "$FISH_CONFIG")"
                echo "alias $target_alias 'sudo $working_filepath'" >> "$FISH_CONFIG"
                echo "    [+] Appended alias link to config.fish"
            fi
        fi
    fi

done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print0)

if [ "$found_files" = false ]; then
    echo "[+] Directory loop complete. No qualifying source scripts mapped."
else
    echo -e "\n[+] Task sequence finalized. Open a fresh terminal or source profiles to sync changes."
fi
