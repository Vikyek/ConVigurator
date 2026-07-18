#!/usr/bin/env bash
# conv-warden.sh
# Enforces Goldwarden and Bitwarden SSH Agent configurations across user directories and shell profiles.
set -euo pipefail

# Resolve the calling user's actual home directory even under sudo execution
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "===================================================="
echo "    ConVigurator: Goldwarden SSH Agent Integrator   "
echo "===================================================="

# Check dependencies
echo -e "\n[*] Auditing Goldwarden system dependencies..."
if ! command -v goldwarden >/dev/null 2>&1; then
    echo "    [!] Warning: goldwarden binary is not installed on this system."
    echo "        Please build it from AUR: git clone https://aur.archlinux.org/goldwarden.git && makepkg -si"
fi
if ! command -v bitwarden >/dev/null 2>&1; then
    echo "    [!] Warning: bitwarden binary is not installed on this system."
    echo "        Please build it from AUR: git clone https://aur.archlinux.org/bitwarden-bin.git && makepkg -si"
fi

# Define the target socket path for Goldwarden
SOCKET_PATH="\$HOME/.goldwarden-ssh-agent.sock"

# Update existing user home directories
echo -e "\n[*] Configuring shell profiles and SSH settings for all users..."
for user_dir in /home/*; do
    [ ! -d "$user_dir" ] && continue
    user_name=$(basename "$user_dir")
    
    # 1. SSH Config setup
    ssh_dir="$user_dir/.ssh"
    ssh_config="$ssh_dir/config"
    
    if [ "$EUID" -ne 0 ]; then
        # Running as standard user, only touch own home
        if [ "$user_dir" != "$REAL_HOME" ]; then
            continue
        fi
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        
        if [ -f "$ssh_config" ] && grep -Fq "IdentityAgent" "$ssh_config"; then
            echo "    -> SSH agent link already defined in $ssh_config"
        else
            echo -e "Host *\n    IdentityAgent ~/.goldwarden-ssh-agent.sock" >> "$ssh_config"
            chmod 600 "$ssh_config"
            echo "    [+] Appended IdentityAgent to $ssh_config"
        fi
    else
        # Running as root, update all users
        mkdir -p "$ssh_dir"
        chown "$user_name":"$user_name" "$ssh_dir"
        chmod 700 "$ssh_dir"
        
        if [ -f "$ssh_config" ] && grep -Fq "IdentityAgent" "$ssh_config"; then
            echo "    -> SSH agent link already defined in $ssh_config"
        else
            echo -e "Host *\n    IdentityAgent ~/.goldwarden-ssh-agent.sock" >> "$ssh_config"
            chown "$user_name":"$user_name" "$ssh_config"
            chmod 600 "$ssh_config"
            echo "    [+] Appended IdentityAgent to $ssh_config"
        fi
    fi

    # 2. Shell Profiles: Bash
    bashrc="$user_dir/.bashrc"
    if [ -f "$bashrc" ]; then
        if grep -Fq "SSH_AUTH_SOCK=" "$bashrc"; then
            # Replace old socket if it pointed somewhere else
            sed -i "s|export SSH_AUTH_SOCK=.*|export SSH_AUTH_SOCK=\"$SOCKET_PATH\"|g" "$bashrc"
            echo "    -> SSH_AUTH_SOCK verified in $bashrc"
        else
            echo "export SSH_AUTH_SOCK=\"$SOCKET_PATH\"" >> "$bashrc"
            echo "    [+] Added SSH_AUTH_SOCK to $bashrc"
        fi
    fi

    # 3. Shell Profiles: Zsh
    zshrc="$user_dir/.zshrc"
    if [ -f "$zshrc" ]; then
        if grep -Fq "SSH_AUTH_SOCK=" "$zshrc"; then
            sed -i "s|export SSH_AUTH_SOCK=.*|export SSH_AUTH_SOCK=\"$SOCKET_PATH\"|g" "$zshrc"
            echo "    -> SSH_AUTH_SOCK verified in $zshrc"
        else
            echo "export SSH_AUTH_SOCK=\"$SOCKET_PATH\"" >> "$zshrc"
            echo "    [+] Added SSH_AUTH_SOCK to $zshrc"
        fi
    fi

    # 4. Shell Profiles: Fish
    fish_config="$user_dir/.config/fish/config.fish"
    if [ -f "$fish_config" ]; then
        if grep -Fq "SSH_AUTH_SOCK" "$fish_config"; then
            sed -i "s|set -gx SSH_AUTH_SOCK.*|set -gx SSH_AUTH_SOCK \"$SOCKET_PATH\"|g" "$fish_config"
            echo "    -> SSH_AUTH_SOCK verified in config.fish"
        else
            echo "set -gx SSH_AUTH_SOCK \"$SOCKET_PATH\"" >> "$fish_config"
            echo "    [+] Added SSH_AUTH_SOCK to config.fish"
        fi
    fi
done

# Output Guidelines and Key Loading Documentation
cat << 'EOF'

====================================================
           VAULT & SSH KEY INITIALIZATION
====================================================
Now that the profiles are integrated, initialize your vault:

1. Launch the daemon:
   $ goldwarden daemonize &

2. Set your Vault PIN:
   $ goldwarden vault setpin

3. Log into your Vault:
   $ goldwarden vault login

4. Storing keys in Bitwarden:
   - Create a new "Secure Note" in your vault.
   - Name the note after your public key filename (e.g. "id_ed25519.pub").
   - Set the Note contents to the public key string (e.g. "ssh-ed25519 AAAAC3Nz...").
   - Create a custom text field in the same note named "private-key".
   - Set the value of the "private-key" field to your PEM-formatted private key:
     -----BEGIN OPENSSH PRIVATE KEY-----
     ...
     -----END OPENSSH PRIVATE KEY-----

Once configured, standard ssh and git requests will unlock and use the keys!
EOF
