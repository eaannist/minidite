#!/usr/bin/env bash
# minidite - Bash configuration
# Optimized for SSH and headless server (no X11/Wayland)

# -----------------------------------------------------------------------------
# Colors and version
# -----------------------------------------------------------------------------
VERSION="$(cat "${HOME}/minidite-version" 2>/dev/null)"
WHITE='\033[37m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
GRAY='\033[90m'
LRED='\033[91m'
LGREEN='\033[92m'
LYELLOW='\033[93m'
LBLUE='\033[94m'
LMAGENTA='\033[95m'
LCYAN='\033[96m'
LWHITE='\033[97m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

AUTHORSTRING="${DIM}by ${LGREEN}e${LYELLOW}a${LMAGENTA}a${LBLUE}n${LGREEN}n${LYELLOW}i${LMAGENTA}s${LBLUE}t${NC}"

# Header logo

show_logo() {
  echo -e "${CYAN}"
  echo -e "
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
                                ${AUTHORSTRING}
                                     ${GRAY}v${VERSION:-N/A}
"
  echo -e "${NC}"
}

# -----------------------------------------------------------------------------
# History and shell options
# -----------------------------------------------------------------------------
HISTFILE="${HOME}/.cache/bash/history"
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
shopt -s checkwinsize

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
export TERM="${TERM:-xterm-256color}"
export EDITOR="${EDITOR:-micro}"
export VISUAL="${VISUAL:-micro}"
export PAGER="${PAGER:-less}"
export PATH="${HOME}/.local/bin:${PATH}"

_path_length=42
_set_tpath() {
  local p="${PWD}"
  if [[ "$p" == "$HOME" ]]; then export TPath='~'
  elif [[ ${#p} -le $_path_length ]]; then export TPath="$p"
  else export TPath="…${p: -$_path_length}"; fi
}
PROMPT_COMMAND="_set_tpath${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# -----------------------------------------------------------------------------
# Optional: Oh My Posh, zoxide, fzf
# -----------------------------------------------------------------------------
OMP_CONFIG="${HOME}/.config/oh-my-posh/theme.omp.json"
if [[ -x "${HOME}/.local/bin/oh-my-posh" ]] && [[ -f "${OMP_CONFIG}" ]]; then
  eval "$("${HOME}/.local/bin/oh-my-posh" init bash --config "${OMP_CONFIG}")"
elif command -v oh-my-posh &>/dev/null && [[ -f "${OMP_CONFIG}" ]]; then
  eval "$(oh-my-posh init bash --config "${OMP_CONFIG}")"
fi
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"
[[ -f "${HOME}/.config/fzf/key-bindings.bash" ]] && source "${HOME}/.config/fzf/key-bindings.bash"
[[ -f "${HOME}/.config/fzf/completion.bash" ]] && source "${HOME}/.config/fzf/completion.bash"
[[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
[[ -f /usr/share/fzf/completion.bash ]] && source /usr/share/fzf/completion.bash

# -----------------------------------------------------------------------------
# Listing (eza)
# -----------------------------------------------------------------------------
alias ls='eza --icons=always --group-directories-first'
alias ll='eza -lh --icons=always --group-directories-first'
alias la='eza -lah --icons=always --group-directories-first'
alias lt='eza --tree --icons=always --group-directories-first'
alias l='eza -1 --icons=always --group-directories-first'
alias la0='eza -lah --no-icons --group-directories-first'

# -----------------------------------------------------------------------------
# Core utils (human-readable, color)
# -----------------------------------------------------------------------------
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------
alias b='cd ..'
alias bb='cd ../..'
alias bbb='cd ../../..'
alias mkcd='mkcdir'

# -----------------------------------------------------------------------------
# System (sudo-aware; trailing space in sudo expands aliases)
# -----------------------------------------------------------------------------
alias sudo='sudo '
alias root='sudo su'
alias reboot='sudo reboot'
alias poweroff='sudo poweroff'
alias shutdown='sudo shutdown'

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------
alias ip='ip -c'
alias ipa='ip -c addr'
alias ipr='ip -c route'
alias ping='ping -c 4'
alias ports='ss -tulpn'

# -----------------------------------------------------------------------------
# Fzf shortcuts
# -----------------------------------------------------------------------------
alias f='fzf'
cdf() { local d; d=$(find "${1:-.}" -type d -not -path '*/\.*' 2>/dev/null | fzf +m --height 40%) && cd "$d"; }
ff() { find "${1:-.}" -type f -not -path '*/\.*' 2>/dev/null | fzf +m --height 40%; }

# -----------------------------------------------------------------------------
# Lazydocker: Docker vs Podman (DOCKER_HOST)
# -----------------------------------------------------------------------------
ld-podman() { export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"; echo "DOCKER_HOST set to Podman socket (lazydocker will use Podman)"; }
ld-reset() { unset -v DOCKER_HOST; echo "DOCKER_HOST unset (lazydocker will use Docker)"; }

# -----------------------------------------------------------------------------
# Functions: files and archives
# -----------------------------------------------------------------------------
nf() {
  [[ -z "$1" ]] && { echo "Usage: nf <filename>"; return 1; }
  touch "$1" && "${EDITOR}" "$1"
}
head() {
  if [[ "$1" == -n ]]; then command head -n "$2" "$3"
  elif [[ -n "$2" ]]; then command head -n "$2" "$1"
  else command head -n 10 "$1"; fi
}
tail() {
  if [[ "$1" == -f || "$1" == --follow ]]; then command tail -f "$2"
  elif [[ "$1" == -n ]]; then command tail -n "$2" "$3"
  elif [[ -n "$2" ]]; then command tail -n "$2" "$1"
  else command tail -n 10 "$1"; fi
}
mkcdir() { mkdir -p "$1" && cd "$1"; }
extract() {
  [[ -z "$1" ]] && { echo "Usage: extract <archive>"; return 1; }
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf "$1" ;; *.tar.xz) tar xJf "$1" ;;
    *.bz2) bunzip2 "$1" ;; *.gz) gunzip "$1" ;; *.tar) tar xf "$1" ;;
    *.tbz2) tar xjf "$1" ;; *.tgz) tar xzf "$1" ;; *.zip) unzip "$1" ;;
    *.Z) uncompress "$1" ;; *.7z) 7z x "$1" 2>/dev/null || true ;;
    *.rar) unrar x "$1" 2>/dev/null || true ;;
    *.deb) ar x "$1" ;; *.tar.zst) tar --zstd -xf "$1" 2>/dev/null || true ;;
    *) echo "Unknown format: $1"; return 1 ;;
  esac
}

# -----------------------------------------------------------------------------
# Functions: network, system, config
# -----------------------------------------------------------------------------
ipp() { curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip; }
sysinfo() {
  if command -v fastfetch &>/dev/null; then
    fastfetch --config "${HOME}/.config/fastfetch/config.jsonc" 2>/dev/null || fastfetch
  else
    echo "fastfetch not installed. Run setup to install it."
  fi
}
profile-edit() { "${EDITOR}" "${HOME}/.bashrc"; }
theme-edit() { "${EDITOR}" "${HOME}/.config/oh-my-posh/theme.omp.json"; }
reload() { source "${HOME}/.bashrc"; }
ssh-lockdown() {
  local ak="$HOME/.ssh/authorized_keys"
  if [[ ! -f "$ak" ]] || [[ ! -s "$ak" ]]; then
    echo "No keys in $ak. Add your client key first:"
    echo "  From your PC: ssh-copy-id $(whoami)@$(hostname -I 2>/dev/null | awk '{print $1}')"
    return 1
  fi
  echo "Keys in authorized_keys:"
  cat "$ak"
  echo ""
  read -rp "Disable password auth and keep key-only access? (yes/no): " confirm
  [[ "$confirm" == "yes" ]] || { echo "Aborted."; return 0; }
  local drop="/etc/ssh/sshd_config.d/91-minidite-nopasswd.conf"
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    printf '# minidite: password auth disabled (key-only access)\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee "$drop" >/dev/null
  else
    sudo grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null || \
      printf '\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
  sudo systemctl reload sshd.service 2>/dev/null && echo "Password auth disabled. Key-only access active." || echo "sshd reload failed."
}
ssh-unlock() {
  sudo rm -f /etc/ssh/sshd_config.d/91-minidite-nopasswd.conf
  sudo systemctl reload sshd.service 2>/dev/null && echo "Password auth re-enabled." || echo "sshd reload failed."
}
snap() {
  sudo snapper -c root create -c number --description "${1:-manual $(date +%Y-%m-%d_%H:%M)}" || return 1
  echo "Snapshot created."
  [[ -x /usr/local/bin/limine-snapper-menu.sh ]] && sudo /usr/local/bin/limine-snapper-menu.sh && echo "Limine boot menu updated."
}
snap-ls() { sudo snapper -c root list; }
snap-diff() {
  [[ -z "$1" ]] && { echo "Usage: snap-diff <num>  (diff between snapshot and current)"; return 1; }
  sudo snapper -c root status "$1"..0
}
snap-rm() {
  [[ -z "$1" ]] && { echo "Usage: snap-rm <num>"; return 1; }
  sudo snapper -c root delete "$1" && echo "Snapshot $1 deleted."
  [[ -x /usr/local/bin/limine-snapper-menu.sh ]] && sudo /usr/local/bin/limine-snapper-menu.sh
}
snap-rollback() {
  [[ -z "$1" ]] && { echo "Usage: snap-rollback <num>  (rollback root to snapshot)"; return 1; }
  local num="$1"
  local snap_path="/.snapshots/${num}/snapshot"
  [[ -d "$snap_path" ]] || { echo "Snapshot $num not found at $snap_path"; return 1; }
  echo "This will:"
  echo "  1. Snapshot current root as backup"
  echo "  2. Replace @ with snapshot #${num}"
  echo "  3. Reboot required after"
  read -rp "Continue? (yes/no): " confirm
  [[ "$confirm" == "yes" ]] || { echo "Aborted."; return 0; }
  local root_dev
  root_dev=$(findmnt -n -o SOURCE /)
  local mnt="/tmp/.snap-rollback-$$"
  sudo mkdir -p "$mnt"
  sudo mount -o subvolid=5 "$root_dev" "$mnt" || { echo "Failed to mount toplevel"; return 1; }
  sudo snapper -c root create --description "pre-rollback-$(date +%Y%m%d_%H%M)" 2>/dev/null || true
  local ts; ts=$(date +%Y%m%d_%H%M%S)
  sudo mv "$mnt/@" "$mnt/@.rollback-${ts}" || { sudo umount "$mnt"; echo "Failed to rename @"; return 1; }
  sudo btrfs subvolume snapshot "$mnt/@snapshots/${num}/snapshot" "$mnt/@" || { sudo mv "$mnt/@.rollback-${ts}" "$mnt/@"; sudo umount "$mnt"; echo "Failed to create snapshot"; return 1; }
  sudo umount "$mnt"
  echo "Rollback done. Old root saved as @.rollback-${ts}"
  echo "Reboot now:  sudo reboot"
}

# -----------------------------------------------------------------------------
# Help: list all aliases and functions with descriptions
# -----------------------------------------------------------------------------
show-help() {
  echo -e "\n${BOLD}${LCYAN}=== Command Reference ===${NC}\n"
  echo -e "${BOLD}${LCYAN}Listing (eza)${NC}"
  echo -e "  ${LYELLOW}ls${NC}     list (icons, dirs first)"
  echo -e "  ${LYELLOW}ll${NC}     list long"
  echo -e "  ${LYELLOW}la${NC}     list all long"
  echo -e "  ${LYELLOW}lt${NC}     list tree"
  echo -e "  ${LYELLOW}l${NC}      list one column"
  echo -e "  ${LYELLOW}la0${NC}    list all long, no icons"
  echo ""
  echo -e "${BOLD}${LCYAN}Core utils${NC}"
  echo -e "  ${LYELLOW}grep, fgrep, egrep${NC}   grep with color"
  echo -e "  ${LYELLOW}df, du, free${NC}         human-readable sizes"
  echo ""
  echo -e "${BOLD}${LCYAN}Navigation${NC}"
  echo -e "  ${LYELLOW}b, bb, bbb${NC}    cd .., ../.., ../../.."
  echo -e "  ${LYELLOW}mkcd <dir>${NC}    create dir and cd into it"
  echo ""
  echo -e "${BOLD}${LCYAN}System${NC}"
  echo -e "  ${LYELLOW}sudo${NC}    (trailing space: expands aliases)"
  echo -e "  ${LYELLOW}root${NC}    sudo su"
  echo -e "  ${LYELLOW}reboot, poweroff, shutdown${NC}  with sudo"
  echo ""
  echo -e "${BOLD}${LCYAN}Network${NC}"
  echo -e "  ${LYELLOW}ip, ipa, ipr${NC}  ip with color, addr, route"
  echo -e "  ${LYELLOW}ping${NC}    ping -c 4"
  echo -e "  ${LYELLOW}ports${NC}   listening ports (ss -tulpn)"
  echo -e "  ${LYELLOW}ipp${NC}     public IP"
  echo ""
  echo -e "${BOLD}${LCYAN}Fzf${NC}"
  echo -e "  ${LYELLOW}f${NC}      fzf"
  echo -e "  ${LYELLOW}cdf${NC}    cd into dir (fuzzy pick)"
  echo -e "  ${LYELLOW}ff${NC}     fuzzy find file (e.g. micro \$(ff))"
  echo -e "  ${GRAY}Bindings: Ctrl+R history, Ctrl+T files, Alt+C cd${NC}"
  echo ""
  echo -e "${BOLD}${LCYAN}Files and archives${NC}"
  echo -e "  ${LYELLOW}nf <file>${NC}       create file and open in editor"
  echo -e "  ${LYELLOW}head [file] [n]${NC} first n lines (default 10)"
  echo -e "  ${LYELLOW}tail [file] [n]${NC} last n lines; tail -f supported"
  echo -e "  ${LYELLOW}extract <archive>${NC} extract .tar.gz, .zip, .tar.xz, .zst, etc."
  echo ""
  echo -e "${BOLD}${LCYAN}Lazydocker (Docker/Podman)${NC}"
  echo -e "  ${LYELLOW}ld-podman${NC}  set DOCKER_HOST to Podman socket"
  echo -e "  ${LYELLOW}ld-reset${NC}   unset DOCKER_HOST (use Docker)"
  echo ""
  echo -e "${BOLD}${LCYAN}Snapshot (Snapper)${NC}"
  echo -e "  ${LYELLOW}snap [desc]${NC}       create manual snapshot (optional description)"
  echo -e "  ${LYELLOW}snap-ls${NC}           list all snapshots"
  echo -e "  ${LYELLOW}snap-diff <num>${NC}   show changes between snapshot and current"
  echo -e "  ${LYELLOW}snap-rm <num>${NC}     delete a snapshot"
  echo -e "  ${LYELLOW}snap-rollback <num>${NC} rollback root to snapshot (requires reboot)"
  echo ""
  echo -e "${BOLD}${LCYAN}SSH${NC}"
  echo -e "  ${LYELLOW}ssh-lockdown${NC}  disable password auth (key-only, interactive)"
  echo -e "  ${LYELLOW}ssh-unlock${NC}    re-enable password auth"
  echo -e "  ${GRAY}From client PC: ssh-copy-id user@server-ip${NC}"
  echo ""
  echo -e "${BOLD}${LCYAN}Config and misc${NC}"
  echo -e "  ${LYELLOW}sysinfo${NC}      system info (fastfetch)"
  echo -e "  ${LYELLOW}profile-edit${NC} edit .bashrc"
  echo -e "  ${LYELLOW}theme-edit${NC}   edit Oh My Posh theme"
  echo -e "  ${LYELLOW}reload${NC}       source .bashrc"
  echo ""
}

[[ -n "$PS1" ]]
show_logo
echo -e "type ${LYELLOW}show-help${NC} for commands reference\n"
[[ -f "${HOME}/.bashrc.local" ]] && source "${HOME}/.bashrc.local"
