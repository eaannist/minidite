#!/bin/bash
# =============================================================================
# minidite - Post-install setup: packages, configs, SSH, containers (interactive)
# =============================================================================
# Run as normal user after first login (after install.sh and reboot).
# Usage: curl -fsSL <url>/setup | bash
# Uses sudo when needed. Reads from /dev/tty for interactive prompts.
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

VERSION="${VERSION:-N/A}"

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/eaannist/minidite/main}"
HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
CONFIG="${HOME}/.config"

CONFIG_FILES=(
  "home/.bashrc:$HOME/.bashrc:1"
  "home/.config/oh-my-posh/theme.omp.json:$CONFIG/oh-my-posh/theme.omp.json:0"
  "home/.config/micro/settings.json:$CONFIG/micro/settings.json:0"
  "home/.config/fastfetch/config.jsonc:$CONFIG/fastfetch/config.jsonc:0"
  "home/.config/fastfetch/minidite.txt:$CONFIG/fastfetch/minidite.txt:0"
  "home/minidite-version:$HOME/minidite-version:0"
)

REQUIRED_DIRS=(
  "$CONFIG/oh-my-posh"
  "$CONFIG/micro"
  "$CONFIG/fastfetch"
  "$CONFIG/fzf"
  "$HOME/.local/bin"
  "$HOME/.cache/bash"
)

RECOMMENDED_PACKAGES=(micro btop zoxide fzf ripgrep eza unzip tree ttf-firacode-nerd fastfetch)

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
# Logging and input helpers (prompts/errors to stderr for command substitution)
# -----------------------------------------------------------------------------
log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[x]${NC} $1"; }
log_ask()   { echo -e "${BLUE}[?]${NC} $1"; }

read_choice() {
  local prompt="$1"
  shift
  local allowed=("$@")
  local choice
  while true; do
    log_ask "$prompt" >&2
    read -r choice </dev/tty
    choice=$(echo "$choice" | tr -d ' ')
    for a in "${allowed[@]}"; do
      if [[ "$choice" == "$a" ]]; then
        echo "$choice"
        return 0
      fi
    done
    log_err "Invalid choice. Enter one of: ${allowed[*]}" >&2
  done
}

read_yes_no() {
  local prompt="$1"
  local choice
  while true; do
    log_ask "$prompt" >&2
    read -r choice </dev/tty
    choice=$(echo "$choice" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    if [[ "$choice" == "yes" ]]; then echo "yes"; return 0; fi
    if [[ "$choice" == "no" ]]; then echo "no"; return 0; fi
    log_err "Invalid. Enter \"yes\" or \"no\"." >&2
  done
}

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
[[ $EUID -ne 0 ]] || { log_err "Run as normal user (script uses sudo when needed)"; exit 1; }
if [[ ! -w "$HOME" ]]; then
  log_err "Cannot write to $HOME"
  echo "  sudo chown -R \$(whoami):\$(whoami) \$HOME"
  exit 1
fi
if [[ -d "$CONFIG" && ! -w "$CONFIG" ]]; then
  log_err "Cannot write to $CONFIG"
  exit 1
fi

# -----------------------------------------------------------------------------
# Helpers: config download, sshd, podman post-install
# -----------------------------------------------------------------------------
download_configs() {
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
  log_ok "Configs installed"
  return 0
}

configure_sshd_minidite() {
  sudo grep -q 'ClientAliveInterval' /etc/ssh/sshd_config 2>/dev/null || \
    printf '\n# minidite\nClientAliveInterval 60\nClientAliveCountMax 3\nTCPKeepAlive yes\nCompression yes\n' | sudo tee -a /etc/ssh/sshd_config >/dev/null
}

podman_post_install() {
  sudo mkdir -p /etc/containers/registries.conf.d
  [[ ! -f /etc/containers/registries.conf.d/10-unqualified-search-registries.conf ]] && \
    echo 'unqualified-search-registries = ["docker.io"]' | sudo tee /etc/containers/registries.conf.d/10-unqualified-search-registries.conf >/dev/null
  grep -q "^$(whoami):" /etc/subuid 2>/dev/null || sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)" 2>/dev/null
  systemctl --user enable --now podman.socket 2>/dev/null && log_ok "Podman socket enabled" || log_warn "Enable podman.socket manually if needed"
}

# =============================================================================
# Main: numbered steps
# =============================================================================
clear
show_logo
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- setup packages and configs${NC}"
echo ""

# ---- Step 1: Directories ----
log_info "Step 1/11: Directories"
for d in "${REQUIRED_DIRS[@]}"; do
  mkdir -p "$d" 2>/dev/null || { log_err "Cannot create $d"; exit 1; }
done
log_ok "Directories ready"
echo ""

# ---- Step 2: Recommended packages ----
log_info "Step 2/11: Recommended CLI packages"
installed_pkgs=()
missing_pkgs=()
for p in "${RECOMMENDED_PACKAGES[@]}"; do
  pacman -Q "$p" &>/dev/null && installed_pkgs+=("$p") || missing_pkgs+=("$p")
done
total=${#RECOMMENDED_PACKAGES[@]}
installed_count=${#installed_pkgs[@]}
missing_count=${#missing_pkgs[@]}
log_info "${installed_count}/${total} installed, ${missing_count} missing."
[[ $missing_count -gt 0 ]] && echo -e "  ${DIM}Missing: ${missing_pkgs[*]}${NC}"
echo ""

if [[ $missing_count -gt 0 ]]; then
  echo "  1) Install missing only  2) Update installed  3) Update and install missing  4) Skip"
  choice_pkgs=$(read_choice "Choice (1-4): " "1" "2" "3" "4")
else
  echo "  1) Update installed  2) Skip"
  choice_pkgs=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$choice_pkgs" == "1" ]] && choice_pkgs="2"
  [[ "$choice_pkgs" == "2" ]] && choice_pkgs="4"
fi
case "$choice_pkgs" in
  1) [[ $missing_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${missing_pkgs[@]}" 2>/dev/null && log_ok "Missing installed" || log_warn "Failed or nothing to do" ;;
  2) [[ $installed_count -gt 0 ]] && sudo pacman -S -u --noconfirm "${installed_pkgs[@]}" 2>/dev/null && log_ok "Updated" || log_info "Nothing to update" ;;
  3)
    [[ $installed_count -gt 0 ]] && sudo pacman -S -u --noconfirm "${installed_pkgs[@]}" 2>/dev/null || true
    [[ $missing_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${missing_pkgs[@]}" 2>/dev/null || true
    log_ok "Update and install done"
    ;;
  4) log_info "Skipped" ;;
esac
echo ""

# ---- Step 3: Config files ----
log_info "Step 3/11: Config files from repo"
config_already=$( [[ -f "$HOME/.bashrc" ]] && grep -q 'minidite' "$HOME/.bashrc" 2>/dev/null && echo 1 || echo 0 )
if [[ "$config_already" -eq 1 ]]; then
  overwrite=$(read_yes_no "Configs already present. Overwrite? (yes/no): ")
  [[ "$overwrite" == "yes" ]] && download_configs || log_info "Skipped"
else
  write_cfg=$(read_yes_no "Download and install config files? (yes/no): ")
  [[ "$write_cfg" == "yes" ]] && { download_configs || exit 1; } || log_info "Skipped"
fi
echo ""

# ---- Step 4: Oh My Posh ----
log_info "Step 4/11: Oh My Posh (prompt theme)"
if command -v oh-my-posh &>/dev/null; then
  log_ok "Already installed"
else
  inst_omp=$(read_yes_no "Install Oh My Posh? (yes/no): ")
  if [[ "$inst_omp" == "yes" ]]; then
    if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
      log_ok "Installed"
      mkdir -p "$CONFIG/oh-my-posh"
      curl -fsSL "${REPO_URL}/home/.config/oh-my-posh/theme.omp.json" -o "$CONFIG/oh-my-posh/theme.omp.json" 2>/dev/null && log_ok "Theme copied" || true
    else
      log_warn "Install failed"
    fi
  else
    log_info "Skipped"
  fi
fi
echo ""

# ---- Step 5: OpenSSH server ----
log_info "Step 5/11: OpenSSH server"
openssh_installed=0
pacman -Q openssh &>/dev/null && openssh_installed=1
if [[ $openssh_installed -eq 1 ]]; then
  echo "  1) Update and ensure configured  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && { sudo pacman -S -u --noconfirm openssh 2>/dev/null || true; configure_sshd_minidite; sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "sshd enabled" || true; }
else
  echo "  1) Install  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  if [[ "$c" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed openssh 2>/dev/null; then
      configure_sshd_minidite
      sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "OpenSSH installed and sshd enabled" || log_warn "sshd enable failed"
    else
      log_warn "Install failed"
    fi
  fi
fi
echo ""

# ---- Step 6: SSH keys ----
log_info "Step 6/11: SSH keys"
has_key=0
has_auth=0
[[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]] && has_key=1
[[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]] && has_auth=1
if [[ $has_key -eq 1 && $has_auth -eq 1 ]]; then
  log_ok "SSH already configured"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [[ $has_key -eq 0 ]]; then
    gen=$(read_yes_no "Generate SSH key pair? (yes/no): ")
    if [[ "$gen" == "yes" ]]; then
      ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "minidite"
      chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
      cat "$HOME/.ssh/id_ed25519.pub" >> "$HOME/.ssh/authorized_keys" 2>/dev/null
      chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
      log_ok "Key created and added to authorized_keys"
      echo ""; echo -e "${BOLD}Public key:${NC}"; cat "$HOME/.ssh/id_ed25519.pub"; echo ""
    fi
  else
    [[ $has_auth -eq 0 ]] && add=$(read_yes_no "Add existing public key to authorized_keys? (yes/no): ") && [[ "$add" == "yes" ]] && \
      { pub=$(ls "$HOME/.ssh/"*.pub 2>/dev/null | head -1); [[ -n "$pub" ]] && cat "$pub" >> "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys" && log_ok "Added to authorized_keys"; }
  fi
fi
echo ""

# ---- Step 7: Docker ----
log_info "Step 7/11: Docker"
docker_installed=0
pacman -Q docker &>/dev/null && docker_installed=1
if [[ $docker_installed -eq 1 ]]; then
  echo "  1) Update  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && { sudo pacman -S -u --noconfirm docker docker-compose 2>/dev/null || true; sudo systemctl enable --now docker.service 2>/dev/null; sudo usermod -aG docker "$(whoami)" 2>/dev/null; }
else
  echo "  1) Install  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  if [[ "$c" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed docker docker-compose 2>/dev/null; then
      sudo systemctl enable --now docker.service 2>/dev/null
      sudo usermod -aG docker "$(whoami)" 2>/dev/null
      log_ok "Docker installed (log out and back in for group)"
      docker_installed=1
    else
      log_warn "Install failed"
    fi
  fi
fi
echo ""

# ---- Step 8: Podman ----
log_info "Step 8/11: Podman"
podman_installed=0
pacman -Q podman &>/dev/null && podman_installed=1
if [[ $podman_installed -eq 1 ]]; then
  echo "  1) Update  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && sudo pacman -S -u --noconfirm podman 2>/dev/null || true
else
  echo "  1) Install  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  if [[ "$c" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed podman 2>/dev/null; then
      log_ok "Podman installed"
      podman_post_install
      podman_installed=1
    else
      log_warn "Install failed"
    fi
  fi
fi
echo ""

# ---- Step 9: Lazydocker ----
log_info "Step 9/11: Lazydocker (TUI for Docker/Podman)"
if [[ $docker_installed -eq 1 || $podman_installed -eq 1 ]]; then
  inst_ld=$(read_yes_no "Install lazydocker? (yes/no): ")
  if [[ "$inst_ld" == "yes" ]]; then
    curl -sSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null && log_ok "Installed to ~/.local/bin" || log_warn "Install failed"
  fi
else
  log_info "Skipped (no Docker/Podman)"
fi
echo ""

# ---- Step 10: fzf bindings ----
log_info "Step 10/11: fzf"
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.bash ]] && cp /usr/share/fzf/key-bindings.bash "$CONFIG/fzf/" 2>/dev/null
  [[ -f /usr/share/fzf/completion.bash ]]   && cp /usr/share/fzf/completion.bash "$CONFIG/fzf/" 2>/dev/null
  log_ok "Bindings copied"
else
  log_info "fzf not installed, skipped"
fi
echo ""

# ---- Step 11: Cleanup and optimizations ----
log_info "Step 11/11: Cleanup and optimizations"
sudo pacman -Scc --noconfirm 2>/dev/null && log_ok "Pacman cache cleared" || log_warn "Cache cleanup skipped"
orphans=$(pacman -Qdtq 2>/dev/null)
[[ -n "$orphans" ]] && sudo pacman -Rns --noconfirm $orphans 2>/dev/null && log_ok "Orphans removed" || true
sudo systemctl enable fstrim.timer 2>/dev/null && log_ok "fstrim.timer enabled" || log_warn "fstrim.timer unavailable"
pacman -Q pacman-contrib &>/dev/null && sudo systemctl enable paccache.timer 2>/dev/null && log_ok "paccache.timer enabled" || true
echo ""

# ---- Done ----
log_ok "Setup complete."
echo ""
echo "  Next:  source ~/.bashrc   or   exec bash"
echo "         Set terminal font to a Nerd Font for icons."
echo ""
