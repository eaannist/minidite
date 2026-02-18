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
  echo -e '
                                            
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
                                            
'
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

# ---- 1. Packages (optional for minimal) ----
log_ask "Install recommended CLI tools (micro, btop, zoxide, fzf, ripgrep, eza, unzip, tree, nerd font, fastfetch)? (y/n, default y): "
read -r inst_pkgs </dev/tty
inst_pkgs=${inst_pkgs:-y}
if [[ "$inst_pkgs" =~ ^[Yy] ]]; then
  PACKAGES=(micro btop zoxide fzf ripgrep eza unzip tree ttf-firacode-nerd fastfetch)
  if sudo pacman -S --noconfirm --needed "${PACKAGES[@]}" 2>/dev/null; then
    log_ok "Packages installed"
  else
    log_warn "Some packages failed (check sudo/network)"
  fi
else
  log_info "Skipping packages (minimal)"
fi

# ---- 2. Dirs ----
for d in "$CONFIG/oh-my-posh" "$CONFIG/micro" "$CONFIG/fastfetch" "$CONFIG/fzf" "$HOME/.local/bin" "$HOME/.cache/bash"; do
  mkdir -p "$d" 2>/dev/null || { log_err "Cannot create $d"; exit 1; }
done
log_ok "Directories ready"

# ---- 3. Configs from repo ----
CONFIG_FILES=(
  "home/.bashrc:$HOME/.bashrc:1"
  "home/.config/oh-my-posh/theme.omp.json:$CONFIG/oh-my-posh/theme.omp.json:0"
  "home/.config/micro/settings.json:$CONFIG/micro/settings.json:0"
  "home/.config/fastfetch/config.jsonc:$CONFIG/fastfetch/config.jsonc:0"
  "home/.config/fastfetch/minidite.txt:$CONFIG/fastfetch/minidite.txt:0"
  "home/minidite-version:$HOME/minidite-version:0"
)
SETUP_ALREADY_RUN=0
[[ -f "$HOME/.bashrc" ]] && grep -q 'minidite' "$HOME/.bashrc" 2>/dev/null && SETUP_ALREADY_RUN=1

do_download_configs() {
  local entry src dest required
  for entry in "${CONFIG_FILES[@]}"; do
    IFS=: read -r src dest required <<< "$entry"
    if curl -fsSL "${REPO_URL}/${src}" -o "$dest" 2>/dev/null; then
      :
    else
      [[ "$required" -eq 1 ]] && { log_err "Failed $src"; touch "$dest"; return 1; }
      log_warn "Failed $src"
    fi
  done
  log_ok "Configs installed (from home/)"
  return 0
}

if [[ $SETUP_ALREADY_RUN -eq 1 ]]; then
  log_ask "Setup already run. Overwrite config files? (yes/no): "
  read -r overwrite </dev/tty
  [[ "$overwrite" =~ ^[Yy][Ee][Ss]$ ]] && { log_info "Overwriting..."; do_download_configs; } || log_info "Skipping config overwrite"
else
  log_info "Downloading configs from repo..."
  do_download_configs || exit 1
fi

# ---- 4. OpenSSH server (optional) ----
echo ""
log_ask "Install and configure OpenSSH server? (y/n, default n): "
read -r inst_ssh </dev/tty
inst_ssh=${inst_ssh:-n}
if [[ "$inst_ssh" =~ ^[Yy] ]]; then
  if sudo pacman -S --noconfirm --needed openssh 2>/dev/null; then
    sudo grep -q 'ClientAliveInterval' /etc/ssh/sshd_config 2>/dev/null || printf '\n# minidite\nClientAliveInterval 60\nClientAliveCountMax 3\nTCPKeepAlive yes\nCompression yes\n' | sudo tee -a /etc/ssh/sshd_config >/dev/null
    sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "OpenSSH installed and sshd enabled" || log_warn "sshd enable/start failed"
  else
    log_warn "OpenSSH install failed"
  fi
else
  log_info "Skipping OpenSSH server"
fi

# ---- 5. SSH keys (for login; useful if OpenSSH server is installed) ----
echo ""
SSH_KEY_EXISTS=0
[[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]] && SSH_KEY_EXISTS=1
SSH_AUTH_READY=0
[[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]] && SSH_AUTH_READY=1

if [[ $SSH_KEY_EXISTS -eq 1 && $SSH_AUTH_READY -eq 1 ]]; then
  log_ok "SSH already configured (key + authorized_keys present), skipping"
else
  log_info "SSH setup"
  if [[ ! -d "$HOME/.ssh" ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi

  if [[ $SSH_KEY_EXISTS -eq 0 ]]; then
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
    if [[ $SSH_AUTH_READY -eq 0 ]]; then
      log_ask "Add existing public key to authorized_keys? (y/n, default y): "
      read -r addkey </dev/tty
      addkey=${addkey:-y}
      if [[ "$addkey" =~ ^[Yy] ]]; then
        pub=$(ls "$HOME/.ssh/"*.pub 2>/dev/null | head -1)
        if [[ -n "$pub" ]]; then
          cat "$pub" >> "$HOME/.ssh/authorized_keys"
          chmod 600 "$HOME/.ssh/authorized_keys"
          log_ok "Added $pub to authorized_keys"
        fi
      fi
    fi
  fi
fi

# ---- 6. Optional: Docker ----
echo ""
log_ask "Install Docker (engine + compose)? (y/n, default n): "
read -r inst_docker </dev/tty
inst_docker=${inst_docker:-n}
if [[ "$inst_docker" =~ ^[Yy] ]]; then
  if sudo pacman -S --noconfirm --needed docker docker-compose 2>/dev/null; then
    sudo systemctl enable --now docker.service 2>/dev/null || true
    sudo usermod -aG docker "$(whoami)" 2>/dev/null || true
    log_ok "Docker installed and enabled (log out and back in for group)"
  else
    log_warn "Docker install failed"
  fi
fi

# ---- 7. Optional: Podman ----
log_ask "Install Podman? (y/n, default n): "
read -r inst_podman </dev/tty
inst_podman=${inst_podman:-n}
if [[ "$inst_podman" =~ ^[Yy] ]]; then
  if sudo pacman -S --noconfirm --needed podman 2>/dev/null; then
    log_ok "Podman installed"
  else
    log_warn "Podman install failed"
  fi
fi

# ---- 8. Oh My Posh (install binary if missing) ----
if command -v oh-my-posh &>/dev/null; then
  log_ok "Oh My Posh already installed"
else
  if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Oh My Posh installed"
  else
    log_warn "Oh My Posh install failed (optional)"
  fi
fi

# ---- 9. fzf (copy bindings for bash if present) ----
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.bash ]] && cp /usr/share/fzf/key-bindings.bash "$CONFIG/fzf/" 2>/dev/null || true
  [[ -f /usr/share/fzf/completion.bash ]]   && cp /usr/share/fzf/completion.bash "$CONFIG/fzf/" 2>/dev/null || true
  log_ok "fzf configured"
fi

# ---- Done ----
echo ""
log_ok "Setup done."
echo ""
echo "  Next:"
echo "    source ~/.bashrc   or   exec bash"
echo "    Set terminal font to Nerd Font for icons"
echo ""
