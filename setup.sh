#!/bin/bash
# minidite - Packages + configs + SSH setup (interactive)
# Run as normal user after first login. Safe to pipe: curl ... | bash (reads from /dev/tty).
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[x]${NC} $1"; }
log_ask()   { echo -e "${BLUE}[?]${NC} $1"; }

show_logo() {
  echo -e "${CYAN}"
  echo '                                              ;                                  '
  echo '                                              ED.                                '
  echo '                           L.                 E#Wi                             ,; '
  echo '                       t   EW:        ,ft t   E###G.       t                 f#i '
  echo '            ..       : Ej  E##;       t#E Ej  E#fD#W;      Ej GEEEEEEEL    .E#t  '
  echo '           ,W,     .Et E#, E###t      t#E E#, E#t t##L     E#,,;;L#K;;.   i#W,   '
  echo '          t##,    ,W#t E#t E#fE#f     t#E E#t E#t  .E#K,   E#t   t#E     L#D.    '
  echo '         L###,   j###t E#t E#t D#G    t#E E#t E#t    j##f  E#t   t#E   :K#Wfff;  '
  echo '       .E#j##,  G#fE#t E#t E#t  f#E.  t#E E#t E#t    :E#K: E#t   t#E   i##WLLLLt '
  echo '      ;WW; ##,:K#i E#t E#t E#t   t#K: t#E E#t E#t   t##L   E#t   t#E    .E#L     '
  echo '     j#E.  ##f#W,  E#t E#t E#t    ;#W,t#E E#t E#t .D#W;    E#t   t#E      f#E:    '
  echo '   .D#L    ###K:   E#t E#t E#t     :K#D#E E#t E#tiW#G.     E#t   t#E       ,WW;   '
  echo '  :K#t     ##D.    E#t E#t E#t      .E##E E#t E#K##i       E#t   t#E        .D#;  '
  echo '  ...      #G      ..  E#t ..         G#E E#t E##D.        E#t    fE          tt  '
  echo '           j           ,;.             fE ,;. E#t          ,;.     :              '
  echo '                                        ,     L:                                 '
  echo -e "${NC}"
}

[[ $EUID -ne 0 ]] || { log_err "Run as normal user (script uses sudo when needed)"; exit 1; }

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/eaannist/minidite/main}"
HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
CONFIG="${HOME}/.config"

if [[ ! -w "$HOME" ]]; then
  log_err "Cannot write to $HOME"
  echo "  sudo chown -R \$(whoami):\$(whoami) \$HOME"
  exit 1
fi
if [[ -d "$CONFIG" && ! -w "$CONFIG" ]]; then
  log_err "Cannot write to $CONFIG"
  echo "  sudo chown -R \$(whoami):\$(whoami) \$HOME"
  exit 1
fi

clear
show_logo
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- setup packages and configs${NC}"
echo ""

# ---- 1. Packages ----
log_info "Installing packages (micro, btop, zoxide, fzf, eza, tmux, Nerd Font, ...)"
PACKAGES=(micro btop zoxide fzf ripgrep fd bat eza tmux rsync xclip xsel wl-clipboard man-db man-pages texinfo wget unzip tree ncdu ttf-firacode-nerd)
if sudo pacman -S --noconfirm --needed "${PACKAGES[@]}" 2>/dev/null; then
  log_ok "Packages installed"
else
  log_warn "Some packages failed (check sudo/network)"
fi

# ---- 2. Dirs ----
for d in "$CONFIG/oh-my-posh" "$CONFIG/zsh" "$CONFIG/fzf" "$HOME/.local/bin" "$HOME/.cache/zsh"; do
  mkdir -p "$d" 2>/dev/null || { log_err "Cannot create $d"; exit 1; }
done
log_ok "Directories ready"

# ---- 3. SSH (interactive) ----
echo ""
log_info "SSH setup"
if [[ ! -d "$HOME/.ssh" ]]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
fi

if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
  log_ask "Generate SSH key pair? (y/n, default y): "
  read -r genkey </dev/tty
  genkey=${genkey:-y}
  if [[ "$genkey" =~ ^[Yy] ]]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "minidite"
    chmod 600 "$HOME/.ssh/id_ed25519"
    chmod 644 "$HOME/.ssh/id_ed25519.pub"
    log_ok "Key created: $HOME/.ssh/id_ed25519"
    cat "$HOME/.ssh/id_ed25519.pub" >> "$HOME/.ssh/authorized_keys" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null || true
    log_ok "Public key added to authorized_keys (this host)"
    echo ""
    echo -e "${BOLD}Your public key (add to other machines / GitHub / Cursor):${NC}"
    echo ""
    cat "$HOME/.ssh/id_ed25519.pub"
    echo ""
  fi
else
  log_ok "SSH key already present"
  log_ask "Add existing public key to authorized_keys? (y/n, default n): "
  read -r addkey </dev/tty
  if [[ "$addkey" =~ ^[Yy] ]]; then
    pub=$(ls "$HOME/.ssh/"*.pub 2>/dev/null | head -1)
    if [[ -n "$pub" ]]; then
      cat "$pub" >> "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      log_ok "Added $pub to authorized_keys"
    fi
  fi
fi

# ---- 4. Configs from repo ----
log_info "Downloading configs..."
curl -fsSL "${REPO_URL}/.zshrc" -o "$HOME/.zshrc" || { log_err "Failed .zshrc"; touch "$HOME/.zshrc"; exit 1; }
log_ok ".zshrc"
curl -fsSL "${REPO_URL}/theme.omp.json" -o "$CONFIG/oh-my-posh/theme.omp.json" 2>/dev/null || log_warn "theme.omp.json failed"
curl -fsSL "${REPO_URL}/.tmux.conf" -o "$HOME/.tmux.conf" 2>/dev/null || log_warn ".tmux.conf failed"
log_ok "Configs installed"

# ---- 5. Oh My Posh ----
if command -v oh-my-posh &>/dev/null; then
  log_ok "Oh My Posh already installed"
else
  if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Oh My Posh installed"
  else
    log_warn "Oh My Posh install failed (optional)"
  fi
fi

# ---- 6. fzf ----
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.zsh ]] && cp /usr/share/fzf/key-bindings.zsh "$CONFIG/fzf/" 2>/dev/null || true
  [[ -f /usr/share/fzf/completion.zsh ]]   && cp /usr/share/fzf/completion.zsh "$CONFIG/fzf/" 2>/dev/null || true
  log_ok "fzf configured"
fi

# ---- Done ----
echo ""
log_ok "Setup done."
echo ""
echo "  Next:"
echo "    source ~/.zshrc   or   exec zsh"
echo "    Set terminal font to Nerd Font for icons"
echo "    tmux: prefix C-b, split | and -"
echo ""
