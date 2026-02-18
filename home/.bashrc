#!/usr/bin/env bash
# minidite - Bash configuration
# Optimized for SSH and headless server (no X11/Wayland)
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_logo() {
  echo -e "${CYAN}"
  echo -e '
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
'
  echo -e "${NC}"
}

HISTFILE="${HOME}/.cache/bash/history"
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
shopt -s checkwinsize

export TERM="${TERM:-xterm-256color}"
_path_length=42
_set_tpath() {
  local p="${PWD}"
  if [[ "$p" == "$HOME" ]]; then export TPath='~'
  elif [[ ${#p} -le $_path_length ]]; then export TPath="$p"
  else export TPath="…${p: -$_path_length}"; fi
}
PROMPT_COMMAND="_set_tpath${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

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

# fzf aliases and helpers (Ctrl+R history, Ctrl+T files, Alt+C cd come from key-bindings)
alias f='fzf'
cdf() { local d; d=$(find . -maxdepth 3 -type d 2>/dev/null | fzf) && cd "$d"; }
ff() { find . -maxdepth 5 -type f 2>/dev/null | fzf; }

export EDITOR="${EDITOR:-micro}"
export VISUAL="${VISUAL:-micro}"
export PAGER="${PAGER:-less}"
export PATH="${HOME}/.local/bin:${PATH}"

# Listing (eza)
alias ls='eza --icons=always --group-directories-first'
alias ll='eza -lh --icons=always --group-directories-first'
alias la='eza -lah --icons=always --group-directories-first'
alias lt='eza --tree --icons=always --group-directories-first'
alias l='eza -1 --icons=always --group-directories-first'
alias la0='eza -lah --no-icons --group-directories-first'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias b='cd ..'
alias bb='cd ../..'
alias bbb='cd ../../..'
alias mkcd='mkcdir'

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
alias sudo='sudo '
alias su='sudo su'
alias root='sudo su'
alias reboot='sudo reboot'
alias poweroff='sudo poweroff'
alias shutdown='sudo shutdown'

# Network (ip, ping, ports, ipp, ipl)
alias ip='ip -c'
alias ipa='ip -c addr'
alias ipr='ip -c route'
alias ping='ping -c 4'
alias ports='ss -tulpn'

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

show-help() {
  echo -e "\n\n${BOLD}${DIM}=== ${YELLOW}Command Reference${DIM} ===${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}DIRECTORIES:${NC}"
  echo -e "  ${YELLOW}b, bb, bbb${NC}            ${DIM}Go up 1, 2, or 3 directories${NC}"
  echo -e "  ${YELLOW}mkcd <dir>${NC}            ${DIM}Create directory and cd into it${NC}"
  echo -e "  ${YELLOW}ls, ll, la, lt, l${NC}     ${DIM}List files (eza; Nerd Font for icons)${NC}"
  echo -e "  ${YELLOW}la0${NC}                   ${DIM}List all without icons${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}FILES:${NC}"
  echo -e "  ${YELLOW}nf <file>${NC}             ${DIM}Create file and open in editor${NC}"
  echo -e "  ${YELLOW}head <file> [n]${NC}       ${DIM}First n lines (default 10)${NC}"
  echo -e "  ${YELLOW}tail <file> [n]${NC}       ${DIM}Last n lines; tail -f supported${NC}"
  echo -e "  ${YELLOW}extract <archive>${NC}     ${DIM}Extract .tar.gz, .zip, .tar.xz, etc.${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}FZF:${NC}"
  echo -e "  ${YELLOW}f${NC}                     ${DIM}Run fzf${NC}"
  echo -e "  ${YELLOW}cdf${NC}                  ${DIM}Cd into directory (fuzzy pick)${NC}"
  echo -e "  ${YELLOW}ff${NC}                   ${DIM}Fuzzy find file (e.g. micro \$(ff))${NC}"
  echo -e "  ${DIM}Key bindings: Ctrl+R history, Ctrl+T files, Alt+C cd${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}GIT:${NC}"
  echo -e "  ${YELLOW}g, ga, gaa${NC}            ${DIM}git, add, add --all${NC}"
  echo -e "  ${YELLOW}gb, gc, gca, gco${NC}      ${DIM}branch, commit, amend, checkout${NC}"
  echo -e "  ${YELLOW}gd, gl, gla${NC}           ${DIM}diff, log, log --all${NC}"
  echo -e "  ${YELLOW}gp, gpl${NC}               ${DIM}push, pull${NC}"
  echo -e "  ${YELLOW}gs, gst, gstp, gsw${NC}    ${DIM}status, stash, stash pop, switch${NC}"
  echo -e "  ${YELLOW}gu-set <name>${NC}         ${DIM}Set git user.name${NC}"
  echo -e "  ${YELLOW}gu-get${NC}                ${DIM}Show git user and email${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}SYSTEM:${NC}"
  echo -e "  ${YELLOW}sysinfo${NC}               ${DIM}System information (fastfetch)${NC}"
  echo ""
  echo -e "${BOLD}${BLUE}NETWORK:${NC}"
  echo -e "  ${YELLOW}ip, ipa, ipr${NC}           ${DIM}IP commands with colors${NC}"
  echo -e "  ${YELLOW}ping${NC}                  ${DIM}Ping 4 packets${NC}"
  echo -e "  ${YELLOW}ports${NC}                 ${DIM}Listening ports (ss -tulpn)${NC}"
  echo -e "  ${YELLOW}ipp${NC}                   ${DIM}Public IP address${NC}\n"
}

[[ -n "$PS1" ]]
show_logo
echo -e "type ${YELLOW}show-help${NC} for commands reference\n"
[[ -f "${HOME}/.bashrc.local" ]] && source "${HOME}/.bashrc.local"
