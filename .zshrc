#!/usr/bin/env zsh
# minidite - Zsh Configuration
# Optimized for SSH and Cursor IDE

HISTFILE="${HOME}/.cache/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE HIST_VERIFY INC_APPEND_HISTORY
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT CDABLE_VARS
setopt COMPLETE_IN_WORD ALWAYS_TO_END AUTO_MENU AUTO_LIST AUTO_PARAM_SLASH COMPLETE_ALIASES

autoload -Uz compinit
compinit -d "${HOME}/.cache/zsh/zcompdump"
bindkey -e

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' rehash true

export TERM="${TERM:-xterm-256color}"
autoload -Uz add-zsh-hook
_path_length=42
function _set_tpath() {
    local p="${PWD}"
    if [[ "$p" == "$HOME" ]]; then export TPath='~'
    elif [[ ${#p} -le $_path_length ]]; then export TPath="$p"
    else export TPath="…${p: -$_path_length}"; fi
}
add-zsh-hook precmd _set_tpath

OMP_CONFIG="${HOME}/.config/oh-my-posh/theme.omp.json"
if [[ -x "${HOME}/.local/bin/oh-my-posh" ]] && [[ -f "${OMP_CONFIG}" ]]; then
    eval "$("${HOME}/.local/bin/oh-my-posh" init zsh --config "${OMP_CONFIG}")"
elif command -v oh-my-posh &> /dev/null && [[ -f "${OMP_CONFIG}" ]]; then
    eval "$(oh-my-posh init zsh --config "${OMP_CONFIG}")"
fi

command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

[[ -f "${HOME}/.config/fzf/key-bindings.zsh" ]] && source "${HOME}/.config/fzf/key-bindings.zsh"
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f "${HOME}/.config/fzf/completion.zsh" ]] && source "${HOME}/.config/fzf/completion.zsh"
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh

export EDITOR="${EDITOR:-micro}"
export VISUAL="${VISUAL:-micro}"
export PAGER="${PAGER:-less}"
export MANPAGER="${MANPAGER:-less}"
export PATH="${HOME}/.local/bin:${PATH}"

alias ls='eza --icons=always --group-directories-first'
alias ll='eza -lh --icons=always --group-directories-first'
alias la='eza -lah --icons=always --group-directories-first'
alias lt='eza --tree --icons=always --group-directories-first'
alias l='eza -1 --icons=always --group-directories-first'
alias la0='eza -lah --no-icons --group-directories-first'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias vim='micro' alias vi='micro' alias edit='micro'
alias top='btop' alias htop='btop'
alias df='df -h' alias du='du -h' alias free='free -h'
alias ..='cd ..' alias ...='cd ../..' alias ....='cd ../../..'
alias b='cd ..' alias bb='cd ../..' alias bbb='cd ../../..'
alias mkcd='mkcdir() { mkdir -p "$1" && cd "$1"; }; mkcdir'
alias g='git' alias ga='git add' alias gaa='git add --all'
alias gb='git branch' alias gc='git commit -v' alias gco='git checkout'
alias gd='git diff' alias gl='git log --oneline --graph --decorate'
alias gla='git log --oneline --graph --decorate --all'
alias gp='git push' alias gpl='git pull' alias gs='git status' alias gst='git stash'
alias sudo='sudo ' alias su='sudo su' alias root='sudo su'
alias ip='ip -c' alias ipa='ip -c addr' alias ipr='ip -c route'
alias ping='ping -c 4' alias ports='ss -tulpn'

command -v wl-copy &>/dev/null && { alias cpy='wl-copy'; alias pst='wl-paste'; }
command -v xclip &>/dev/null && { alias cpy='xclip -selection clipboard'; alias pst='xclip -selection clipboard -o'; }
command -v xsel &>/dev/null && { alias cpy='xsel --clipboard --input'; alias pst='xsel --clipboard --output'; }

function nf() { touch "$1" && "${EDITOR}" "$1"; }
function head() { command head -n "${2:-10}" "$1"; }
function tail() { [[ "$1" == -f || "$1" == --follow ]] && command tail -f "$2" || command tail -n "${2:-10}" "$1"; }
function ff() { fd -H "$1" "${2:-.}"; }
function mkcdir() { mkdir -p "$1" && cd "$1"; }
function extract() {
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf "$1" ;; *.tar.xz) tar xJf "$1" ;;
    *.zip) unzip "$1" ;; *.tar) tar xf "$1" ;; *) echo "Unknown format: $1" ;;
  esac
}
function ip-pub() { curl -s ifconfig.me || curl -s icanhazip.com; }
function ip-local() { ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1; }
function sysinfo() { echo "Hostname: $(hostname)" "Kernel: $(uname -r)" "Uptime: $(uptime -p 2>/dev/null)"; free -h | head -2; df -h / | tail -1; }
function gu-set() { git config user.name "$1"; echo "Git user: $1"; }
function gu-get() { echo "Name: $(git config user.name)" "Email: $(git config user.email)"; }
function profile-edit() { "${EDITOR}" "${HOME}/.zshrc"; }
function theme-edit() { "${EDITOR}" "${HOME}/.config/oh-my-posh/theme.omp.json"; }
function reload() { source "${HOME}/.zshrc"; }

function show-help() {
  echo "minidite commands: profile-edit, theme-edit, reload, show-help"
  echo "Dirs: b, bb, bbb, mkcd <dir>  |  Files: ls, ll, la, la0, edit, nf"
  echo "Git: g, ga, gs, gp, gpl, gu-set, gu-get  |  System: sysinfo, ip-pub, ip-local, top, ports"
}

[[ -o interactive ]] && echo -e "\033[0;36mminidite\033[0m - type show-help"
[[ -f "${HOME}/.zshrc.local" ]] && source "${HOME}/.zshrc.local"
