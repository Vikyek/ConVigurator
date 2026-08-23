#!/usr/bin/env bash
# conv-agy.sh
# Master setup script for Antigravity (AGY) tools, configuration, and plugins.
set -euo pipefail

echo "=========================================="
echo "    ConVigurator: Antigravity Setup"
echo "=========================================="

# 1. Ensure antigravity-cli is installed
echo -e "\n[*] Checking antigravity-cli..."
if ! command -v agy &>/dev/null; then
    echo "    [+] Installing antigravity-cli via paru..."
    paru -S --noconfirm --needed antigravity-cli
else
    echo "    [+] antigravity-cli is already installed."
fi

# 2. Clone/update private config vault
echo -e "\n[*] Configuring private config vault (agy-syncvault)..."
mkdir -p ~/.gemini
if [ ! -d ~/.gemini/config/.git ]; then
    echo "    [+] Cloning agy-syncvault to ~/.gemini/config..."
    gh repo clone Vikyek/agy-syncvault ~/.gemini/config
else
    echo "    [+] agy-syncvault already cloned. Pulling updates..."
    cd ~/.gemini/config
    git pull --rebase origin main || echo "    [!] Warning: failed to pull latest vault changes."
fi

# 3. Install/update tokless pipeline
echo -e "\n[*] Setting up tokless pipeline..."
curl -fsSL https://raw.githubusercontent.com/HoangP8/tokless/main/scripts/install.sh | bash
~/.local/bin/tokless
~/.local/bin/tokless doctor

# 4. Install/update agy-vispatcher plugin
echo -e "\n[*] Checking agy-vispatcher plugin..."
mkdir -p ~/.gemini/config/plugins
if [ ! -d ~/.gemini/config/plugins/agy-vispatcher/.git ]; then
    echo "    [+] Cloning agy-vispatcher..."
    gh repo clone Vikyek/agy-vispatcher ~/.gemini/config/plugins/agy-vispatcher
else
    echo "    [+] agy-vispatcher is already installed."
fi

# 5. Install/update toon-mcp server
echo -e "\n[*] Configuring toon-mcp server..."
python3 -m venv ~/.local/share/toon-venv
~/.local/share/toon-venv/bin/pip install --upgrade pip
rm -rf /tmp/toon-mcp-install
echo "    [+] Cloning and installing toon-mcp..."
gh repo clone Vikyek/toon-mcp /tmp/toon-mcp-install -- --depth=1
~/.local/share/toon-venv/bin/pip install /tmp/toon-mcp-install
rm -rf /tmp/toon-mcp-install

# 6. Deploy configurations and hooks
echo -e "\n[*] Deploying configurations and hooks..."
if [ -f ~/.gemini/config/hooks.json ]; then
    ln -sf ~/.gemini/config/hooks.json ~/.gemini/hooks.json 2>/dev/null || cp ~/.gemini/config/hooks.json ~/.gemini/hooks.json
    echo "    [+] Hooks linked."
else
    echo "    [!] Warning: ~/.gemini/config/hooks.json not found."
fi

if [ -f ~/.gemini/config/mcp_config.json ]; then
    ln -sf ~/.gemini/config/mcp_config.json ~/.gemini/mcp_config.json 2>/dev/null || cp ~/.gemini/config/mcp_config.json ~/.gemini/mcp_config.json
    echo "    [+] MCP configuration linked."
else
    echo "    [!] Warning: ~/.gemini/config/mcp_config.json not found."
fi

echo -e "\n[+] Antigravity environment bootstrap complete!"
