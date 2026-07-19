# ConVigurator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ConVigurator** is a modular system configuration, shell environment, and recovery layout coordinator designed specifically for Arch Linux and Garuda setups. It automates profile setups, configures active aliases, handles browser configurations, and manages recovery tools with clean user/root synchronization.

---

## 🛠️ Included Tools & Modules

The suite contains the following modules, which are automatically registered as global system aliases:

| Command Alias | Script Source | Purpose | Key Target Files |
| --- | --- | --- | --- |
| `conv-install` | `install.sh` | Master setup script that registers tools as aliases, normalizes files, installs systemd units, and synchronizes environments. | Shell profiles (`.bashrc`, `.zshrc`, `config.fish`) |
| `conv-alias` | `conv-alias.sh` | Audits and normalizes user-defined shell aliases against system policies. | User profile configs |
| `conv-shell` | `configure-shell.sh` / `conv-shell.sh` | Installs clean Fish & Starship prompt configurations with an **adaptive timeout tuner**. | `~/.config/fish/config.fish`, `~/.config/starship.toml` |
| `conv-warden` | `conv-warden.sh` | Links SSH configuration profiles to utilize the Goldwarden/Bitwarden agent socket. | `~/.ssh/config`, shell profiles |
| `conv-deamonbreak`| `deamonbreak.sh` | Diagnostic utility to inspect and reset locked system daemons. | Process table |
| `conv-firedragon-allow-fox` | `firedragon-allow-fox.sh` | Synchronizes profile settings and allowances between Firedragon and Firefox. | Web browser profiles |
| `conv-micro-allow-global-c` | `micro-allow-global-c.sh` | Configures the micro editor skeleton settings to enforce global clipboard access. | `~/.config/micro/settings.json` |
| `conv-system-snapshot` | `system-snapshot.sh` | Manages automated user-home and system snapshots. | `/etc/snapper/configs/` |
| `conv-encrypt-root-offline` | `encrypt-root-offline.sh` | Step-by-step utility for offline LUKS partition encryptions during recovery. | Disk partitions |
| `conv-boot` | `conv-boot.sh` | ConVigurator Boot Configuration Tuner to dynamically audit hardware (touchscreen) and filesystem (Btrfs) to toggle/scale service states at startup. | `/etc/systemd/system/conv-boot.service` |
| `conv-build` | `conv-build.sh` | VelocityOS ConVigurator Live ISO Architect that rebuilds a monolithic ISO image from the active live overlay layout. | `/mnt/temp` staging path |
| `conv-backup-firedragon-pr` | `backup-firedragon-pr.sh` | Backup utility for Firedragon profiles and user preferences. | Web browser profiles |
| `conv-fish` | `conv-fish.sh` | Helper environment utilities and fish configuration setup scripts. | `config.fish` |
| `conv-installer` | `conv-installer.sh` | Installer profile coordinator script configuration backup. | `/usr/local/bin` |

---

## 🚀 Installation & Initialization

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/Vikyek/ConVigurator.git
   cd ConVigurator
   ```

2. **Run the Master Installer:**
   ```bash
   ./install.sh
   ```

3. **Source Profiles:**
   Apply the environment changes instantly:
   ```bash
   source ~/.config/fish/config.fish
   ```

---

## 🔧 Adaptive Timeout System

The custom Fish shell configuration features a background **auto-tuning system** (`__starship_auto_tune`). It runs silently on interactive terminal logins:
* It reads the Starship prompt logs (`~/.cache/starship/session_*.log`) to detect timing warnings.
* If command execution (such as `sudo` checks or `node`/`npm` scans) begins to lag, it dynamically scales up the `command_timeout` and `scan_timeout` parameters in `~/.config/starship.toml` to prevent terminal hangs.
* It parses files cleanly without wildcard errors even if the cache is empty.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
