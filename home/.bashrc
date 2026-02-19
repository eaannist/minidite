#!/usr/bin/env bash
# minidite - Bash configuration
# Optimized for SSH and headless server (no X11/Wayland)

# -----------------------------------------------------------------------------
# Colors and version
# -----------------------------------------------------------------------------
VERSION="$(cat "${HOME}/minidite-version" 2>/dev/null)"
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Header logo

show_logo() {
  echo -e "${CYAN}"
  echo -e "
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
                                     ${DIM}v${VERSION:-N/A}
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
# Git
# -----------------------------------------------------------------------------
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gc='git commit -v'
alias gca='git commit -v --amend'
alias gco='git checkout'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'
alias gla='git log --oneline --graph --decorate --all'
alias gp='git push'
alias gpl='git pull'
alias gs='git status'
alias gst='git stash'
alias gstp='git stash pop'
alias gsw='git switch'

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
gu-set() { [[ -z "$1" ]] && { echo "Usage: gu-set <username>"; return 1; }; git config user.name "$1"; echo "Git user: $1"; }
gu-get() { echo "Name: $(git config user.name)" "Email: $(git config user.email)"; }
profile-edit() { "${EDITOR}" "${HOME}/.bashrc"; }
theme-edit() { "${EDITOR}" "${HOME}/.config/oh-my-posh/theme.omp.json"; }
reload() { source "${HOME}/.bashrc"; }
snap() {
  sudo snapper -c root create --description "${1:-manual $(date +%Y-%m-%d_%H:%M)}" || return 1
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
  echo -e "\n${BOLD}${DIM}${YELLOW}=== Command Reference ===${NC}\n"
  echo -e "${BOLD}${BLUE}Listing (eza)${NC}"
  echo -e "  ${YELLOW}ls${NC}     list (icons, dirs first)"
  echo -e "  ${YELLOW}ll${NC}     list long"
  echo -e "  ${YELLOW}la${NC}     list all long"
  echo -e "  ${YELLOW}lt${NC}     list tree"
  echo -e "  ${YELLOW}l${NC}      list one column"
  echo -e "  ${YELLOW}la0${NC}    list all long, no icons"
  echo ""
  echo -e "${BOLD}${BLUE}Core utils${NC}"
  echo -e "  ${YELLOW}grep, fgrep, egrep${NC}   grep with color"
  echo -e "  ${YELLOW}df, du, free${NC}         human-readable sizes"
  echo ""
  echo -e "${BOLD}${BLUE}Navigation${NC}"
  echo -e "  ${YELLOW}b, bb, bbb${NC}    cd .., ../.., ../../.."
  echo -e "  ${YELLOW}mkcd <dir>${NC}    create dir and cd into it"
  echo ""
  echo -e "${BOLD}${BLUE}Git${NC}"
  echo -e "  ${YELLOW}g${NC}       git"
  echo -e "  ${YELLOW}ga, gaa${NC} add, add --all"
  echo -e "  ${YELLOW}gb${NC}      branch"
  echo -e "  ${YELLOW}gc, gca${NC} commit -v, commit --amend"
  echo -e "  ${YELLOW}gco, gsw${NC} checkout, switch"
  echo -e "  ${YELLOW}gd${NC}      diff"
  echo -e "  ${YELLOW}gl, gla${NC} log oneline graph, log --all"
  echo -e "  ${YELLOW}gp, gpl${NC} push, pull"
  echo -e "  ${YELLOW}gs${NC}      status"
  echo -e "  ${YELLOW}gst, gstp${NC} stash, stash pop"
  echo -e "  ${YELLOW}gu-set <name>${NC}  set git user.name"
  echo -e "  ${YELLOW}gu-get${NC}  show git user and email"
  echo ""
  echo -e "${BOLD}${BLUE}System${NC}"
  echo -e "  ${YELLOW}sudo${NC}    (trailing space: expands aliases)"
  echo -e "  ${YELLOW}root${NC}    sudo su"
  echo -e "  ${YELLOW}reboot, poweroff, shutdown${NC}  with sudo"
  echo ""
  echo -e "${BOLD}${BLUE}Network${NC}"
  echo -e "  ${YELLOW}ip, ipa, ipr${NC}  ip with color, addr, route"
  echo -e "  ${YELLOW}ping${NC}    ping -c 4"
  echo -e "  ${YELLOW}ports${NC}  listening ports (ss -tulpn)"
  echo -e "  ${YELLOW}ipp${NC}    public IP (function)"
  echo ""
  echo -e "${BOLD}${BLUE}Fzf${NC}"
  echo -e "  ${YELLOW}f${NC}      fzf"
  echo -e "  ${YELLOW}cdf${NC}    cd into dir (fuzzy pick)"
  echo -e "  ${YELLOW}ff${NC}     fuzzy find file (e.g. micro \$(ff))"
  echo -e "  ${DIM}Bindings: Ctrl+R history, Ctrl+T files, Alt+C cd${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}Files and archives${NC}"
  echo -e "  ${YELLOW}nf <file>${NC}       create file and open in editor"
  echo -e "  ${YELLOW}head [file] [n]${NC} first n lines (default 10)"
  echo -e "  ${YELLOW}tail [file] [n]${NC} last n lines; tail -f supported"
  echo -e "  ${YELLOW}extract <archive>${NC} extract .tar.gz, .zip, .tar.xz, .zst, etc."
  echo ""
  echo -e "${BOLD}${BLUE}Lazydocker (Docker/Podman)${NC}"
  echo -e "  ${YELLOW}ld-podman${NC}  set DOCKER_HOST to Podman socket"
  echo -e "  ${YELLOW}ld-reset${NC}   unset DOCKER_HOST (use Docker)"
  echo ""
  echo -e "${BOLD}${BLUE}Snapshot (Snapper)${NC}"
  echo -e "  ${YELLOW}snap [desc]${NC}       create manual snapshot (optional description)"
  echo -e "  ${YELLOW}snap-ls${NC}           list all snapshots"
  echo -e "  ${YELLOW}snap-diff <num>${NC}   show changes between snapshot and current"
  echo -e "  ${YELLOW}snap-rm <num>${NC}     delete a snapshot"
  echo -e "  ${YELLOW}snap-rollback <num>${NC} rollback root to snapshot (requires reboot)"
  echo ""
  echo -e "${BOLD}${BLUE}Config and misc${NC}"
  echo -e "  ${YELLOW}sysinfo${NC}      system info (fastfetch)"
  echo -e "  ${YELLOW}profile-edit${NC} edit .bashrc"
  echo -e "  ${YELLOW}theme-edit${NC}   edit Oh My Posh theme"
  echo -e "  ${YELLOW}reload${NC}       source .bashrc"
  echo ""
}

[[ -n "$PS1" ]]
show_logo
echo -e "type ${YELLOW}show-help${NC} for commands reference\n"
[[ -f "${HOME}/.bashrc.local" ]] && source "${HOME}/.bashrc.local"
