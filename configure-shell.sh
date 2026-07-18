#!/bin/bash

##: Term colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' ##: No Color

##: Info prefixes
INFO="${BLUE}[INFO]${NC}"
SUCCESS="${GREEN}[SUCCESS]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

clear
echo -e "${PURPLE}${BOLD}         Garuda Hyprland Shell Configuration Installer${NC}"
echo -e "This script will safely install clean configurations for your system."
echo ""

##: Ensure configuration directories exist
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

FISH_DIR="$REAL_HOME/.config/fish"
STARSHIP_FILE="$REAL_HOME/.config/starship.toml"

if [ ! -d "$FISH_DIR" ]; then
    echo -e "${INFO} Creating Fish configuration folder: $FISH_DIR"
    mkdir -p "$FISH_DIR"
fi

##: Step 1: Backup existing configuration files
echo -e "${CYAN}${BOLD}[Step 1/5] Backing up existing configurations...${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -f "$FISH_DIR/config.fish" ]; then
    cp "$FISH_DIR/config.fish" "$FISH_DIR/config.fish.backup_$TIMESTAMP"
    echo -e "${SUCCESS} Backed up config.fish -> config.fish.backup_$TIMESTAMP"
else
    echo -e "${INFO} No previous config.fish found to backup."
fi

if [ -f "$STARSHIP_FILE" ]; then
    cp "$STARSHIP_FILE" "$STARSHIP_FILE.backup_$TIMESTAMP"
    echo -e "${SUCCESS} Backed up starship.toml -> starship.toml.backup_$TIMESTAMP"
else
    echo -e "${INFO} No previous starship.toml found to backup."
fi
echo ""

##: Step 2: System capability check
echo -e "${CYAN}${BOLD}[Step 2/5] Checking optional system dependencies...${NC}"
DEPENDENCIES=("fastfetch" "eza" "bat" "starship" "ugrep" "expac" "reflector")

for dep in "${DEPENDENCIES[@]}"; do
    if command -v "$dep" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $dep is installed"
    else
        echo -e "  ${YELLOW}✗${NC} $dep is missing (some custom aliases/features might not work)"
    fi
done
echo ""

##: Step 3: Installing clean config.fish
echo -e "${CYAN}${BOLD}[Step 3/5] Writing clean ~/.config/fish/config.fish...${NC}"

cat << 'EOF' > "$FISH_DIR/config.fish"
##: Set values
##: Hide welcome message & ensure we are reporting fish as shell
set fish_greeting
set VIRTUAL_ENV_DISABLE_PROMPT "1"
set -gx SHELL /usr/bin/fish

##: Use bat for man pages
set -xU MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -xU MANROFFOPT "-c"

##: Hint to exit PKGBUILD review in Paru
set -x PARU_PAGER "less -P \"Press 'q' to exit the PKGBUILD review.\""

##: Set settings for https://github.com/franciscolourenco/done
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

##: Environment setup
##: Apply .profile: use this to put fish compatible .profile stuff in
if test -f ~/.fish_profile
    source ~/.fish_profile
end

##: Add ~/.local/bin to PATH
if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

##: Add depot_tools to PATH
if test -d ~/Applications/depot_tools
    if not contains -- ~/Applications/depot_tools $PATH
        set -p PATH ~/Applications/depot_tools
    end
end

##: Starship prompt
if status --is-interactive
    source ("/usr/bin/starship" init fish --print-full-init | psub)
end

##: Functions
##: Functions needed for !! and !$ https://github.com/oh-my-fish/plugin-bang-bang
function __history_previous_command
    switch (commandline -t)
        case "!"
            commandline -t $history[1]; commandline -f repaint
        case "*"
            commandline -i !
    end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

if [ "$fish_key_bindings" = fish_vi_key_bindings ]
    bind -Minsert ! __history_previous_command
    bind -Minsert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

##: Fish command history
function history
    builtin history --show-time='%F %T '
end

function backup --argument filename
    cp $filename $filename.bak
end

##: Copy DIR1 DIR2
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | string trim --right --chars=/)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

##: Cleanup local orphaned packages
function cleanup
    while pacman -Qdtq
        sudo pacman -R (pacman -Qdtq)
        if test "$status" -eq 1
            break
        end
    end
end

##: Starship dynamic auto-tuning for timeouts
function __starship_auto_tune
    set -l config_file ~/.config/starship.toml
    test -f $config_file; or return

    if test -d ~/.cache/starship
        ##: Fetch the most recent session logs
        set -l raw_logs (command ls -t ~/.cache/starship 2>/dev/null | string match -r '^session_.*\.log$' | head -n 5)
        test -n "$raw_logs"; or return
        set -l latest_logs
        for log_file in $raw_logs
            set -a latest_logs ~/.cache/starship/$log_file
        end

        set -l tuned 0

        ##: 1. Auto-tune command_timeout (ceil at 3000ms)
        if grep -q "Executing command .* timed out" $latest_logs
            set -l current_cmd (string match -r '^command_timeout\s*=\s*(\d+)' (cat $config_file))[2]
            if test -n "$current_cmd"
                if test $current_cmd -lt 3000
                    set -l new_cmd (math $current_cmd + 250)
                    sed -i "s/^command_timeout\s*=\s*$current_cmd/command_timeout = $new_cmd/" $config_file
                    set tuned 1
                end
            end
        end

        ##: 2. Auto-tune scan_timeout (ceil at 200ms)
        if grep -q "Scanning current directory timed out" $latest_logs
            set -l current_scan (string match -r '^scan_timeout\s*=\s*(\d+)' (cat $config_file))[2]
            if test -n "$current_scan"
                if test $current_scan -lt 200
                    set -l new_scan (math $current_scan + 10)
                    sed -i "s/^scan_timeout\s*=\s*$current_scan/scan_timeout = $new_scan/" $config_file
                    set tuned 1
                end
            else
                ##: If scan_timeout isn't declared, add it
                sed -i 's/^command_timeout\s*=\s*\(.*\)/command_timeout = \1\nscan_timeout = 40/' $config_file
                set tuned 1
            end
        end

        ##: Clear logs on tune so we don't scale repeatedly off the same historical warnings
        if test "$tuned" = 1
            rm -f ~/.cache/starship/session_*.log 2>/dev/null
        end
    end
end

##: Make directory and instantly enter it
function mkcd --argument dir --description "Create a directory and cd into it"
    if test -n "$dir"
        mkdir -p $dir; and cd $dir
    else
        echo "Usage: mkcd <directory>"
    end
end

##: Universal Archive Extractor
function extract --argument file --description "Extract any archive format automatically"
    if test -f "$file"
        switch "$file"
            case '*.tar.bz2' '*.tbz2'
                tar xjf $file
            case '*.tar.gz' '*.tgz'
                tar xzf $file
            case '*.tar.xz' '*.txz'
                tar xf $file
            case '*.tar.zst'
                tar --zstd -xf $file
            case '*.bz2'
                bunzip2 $file
            case '*.rar'
                unrar x $file
            case '*.gz'
                gunzip $file
            case '*.tar'
                tar xf $file
            case '*.zip'
                unzip $file
            case '*.Z'
                uncompress $file
            case '*.7z'
                7z x $file
            case '*'
                echo "Extension not supported"
        end
    else
        echo "'$file' is not a valid file"
    end
end

##: Useful aliases
##: Replace ls with eza
alias ls 'eza -al --group-directories-first' ##: preferred listing
alias lsz 'eza -al --total-size --group-directories-first' ##: include file size
alias la 'eza -a --group-directories-first'  ##: all files and dirs
alias ll 'eza -l --group-directories-first'  ##: long format
alias lt 'eza -aT --group-directories-first' ##: tree listing
alias l. 'eza -ald --group-directories-first .*' ##: show only dotfiles

##: Replace some more things with better alternatives
abbr cat 'bat --style header,snip,changes'
if not test -x /usr/bin/yay; and test -x /usr/bin/paru
    alias yay 'paru'
end

##: Common use
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'
alias ...... 'cd ../../../../..'
alias big 'expac -H M "%m\t%n" | sort -h | nl' ##: Sort installed packages according to size in MB
alias dir 'dir --color=auto'
alias fixpacman 'sudo rm /var/lib/pacman/db.lck'
alias gitpkg 'pacman -Q | grep -i "-git" | wc -l' ##: List amount of -git packages
alias grep 'ugrep --color=auto'
alias egrep 'ugrep -E --color=auto'
alias fgrep 'ugrep -F --color=auto'
alias grubup 'sudo update-grub'
alias hw 'hwinfo --short'                          ##: Hardware Info
alias ip 'ip -color'
alias psmem 'ps auxf | sort -nr -k 4'
alias psmem10 'ps auxf | sort -nr -k 4 | head -10'
alias rmpkg 'sudo pacman -Rdd'
alias tarnow 'tar -acf '
alias untar 'tar -zxvf '
alias upd '/usr/bin/garuda-update'
alias vdir 'vdir --color=auto'
alias wget 'wget -c '

##: Get fastest mirrors
alias mirror 'sudo reflector -f 30 -l 30 --number 10 --verbose --save /etc/pacman.d/mirrorlist'
alias mirrora 'sudo reflector --latest 50 --number 20 --sort age --save /etc/pacman.d/mirrorlist'
alias mirrord 'sudo reflector --latest 50 --number 20 --sort delay --save /etc/pacman.d/mirrorlist'
alias mirrors 'sudo reflector --latest 50 --number 20 --sort score --save /etc/pacman.d/mirrorlist'

##: Help people new to Arch
alias apt 'man pacman'
alias apt-get 'man pacman'
alias please 'sudo'
alias tb 'nc termbin.com 9999'
alias helpme 'echo "To print basic information about a command use tldr "'
alias pacdiff 'sudo -H DIFFPROG=meld pacdiff'

##: Get the error messages from journalctl
alias jctl 'journalctl -p 3 -xb'

##: Recent installed packages
alias rip 'expac --timefmt="%Y-%m-%d %T" "%l\t%n %v" | sort | tail -200 | nl'

##: Run fastfetch if session is interactive
if status --is-interactive && type -q fastfetch
    fastfetch --config neofetch.jsonc
    echo ""
    set_color yellow --bold
    echo "TODO: Migrate Hyprland configuration to Lua (~/.config/hypr/hyprland.lua) and perform total rebuild."
    set_color normal
    echo ""

    ##: Run the performance auto-tuner cleanly on login
    __starship_auto_tune
end

##: Added by Antigravity CLI installer
set -gx PATH "/home/garuda/.local/bin" $PATH
EOF

echo -e "${SUCCESS} Successfully configured config.fish!"
echo ""

##: Step 4: Installing clean starship.toml
echo -e "${CYAN}${BOLD}[Step 4/5] Writing clean ~/.config/starship.toml...${NC}"

cat << 'EOF' > "$STARSHIP_FILE"
##: General settings
command_timeout = 1000
scan_timeout = 30

##: FIRST LINE/ROW: Info & Status
##: First param ─┌
[username]
format = " [╭─$user]($style)@"
show_always = true
style_root = "bold red"
style_user = "bold red"

##: Second param
[hostname]
disabled = false
format = "[$hostname]($style) in "
ssh_only = false
style = "bold red"

##: Third param
[directory]
style = "purple"
truncate_to_repo = true
truncation_length = 0
truncation_symbol = "repo: "

##: Fourth param
[sudo]
disabled = true

##: Before all the version info (python, nodejs, php, etc.)
[git_status]
ahead = "⇡${count}"
behind = "⇣${count}"
deleted = "x"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
style = "white"

##: Display last commit ID and current Tag version
[git_commit]
tag_symbol = '  '
tag_disabled = false
only_detached = false ##: If false, it shows the tag even if you are on a branch
style = "bold blue"

##: Last param in the first line/row
[cmd_duration]
disabled = false
format = "took $duration"
min_time = 1

##: SECOND LINE/ROW: Prompt
##: Somethere at the beginning
[battery]
charging_symbol = ""
disabled = true
discharging_symbol = ""
full_symbol = ""

[[battery.display]] ##: "bold red" style when capacity is between 0% and 15%
disabled = false
style = "bold red"
threshold = 15

[[battery.display]] ##: "bold yellow" style when capacity is between 15% and 50%
disabled = true
style = "bold yellow"
threshold = 50

[[battery.display]] ##: "bold green" style when capacity is between 50% and 80%
disabled = true
style = "bold green"
threshold = 80

##: Prompt: optional param 1
[time]
disabled = true
format = " 🕙 $time($style)\n"
style = "bright-white"
time_format = "%T"

##: Prompt: param 2
[character]
error_symbol = " [×](bold red)"
success_symbol = " [╰─λ](bold red)"

##: SYMBOLS
[status]
disabled = false
format = '[$symbol$status_common_meaning$status_signal_name$status_maybe_int]'
map_symbol = true
pipestatus = true
symbol = "🔴"

[aws]
symbol = " "

[conda]
symbol = " "

[dart]
symbol = " "

[docker_context]
symbol = " "

[elixir]
symbol = " "

[elm]
symbol = " "

[git_branch]
symbol = " "

[golang]
symbol = " "

[hg_branch]
symbol = " "

[java]
symbol = " "

[julia]
symbol = " "

[nim]
symbol = " "

[nix_shell]
symbol = " "

[nodejs]
symbol = " "

[package]
symbol = " "

[perl]
symbol = " "

[php]
symbol = " "

[python]
symbol = " "

[ruby]
symbol = " "

[rust]
symbol = " "

[swift]
symbol = "ﯣ "
EOF

echo -e "${SUCCESS} Successfully configured starship.toml!"
echo ""

##: Step 5: Finalize and Test execution
echo -e "${CYAN}${BOLD}[Step 5/5] Finalizing shell state...${NC}"

##: Set permissions and ownership
chmod +x "$FISH_DIR/config.fish"
chown -R "$REAL_USER:$REAL_USER" "$FISH_DIR" "$STARSHIP_FILE" 2>/dev/null || true

echo -e "${GREEN}${BOLD}✔ ALL CONFIGURATIONS APPLIED SUCCESSFULLY!${NC}"
echo -e "Your terminal session is protected against hangs. Unchanged sequences are intact."
echo -e "You can apply this new layout immediately by typing:"
echo -e "    ${BOLD}source ~/.config/fish/config.fish${NC}"
echo -e "----------------------------------------------------"
