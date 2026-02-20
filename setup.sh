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
readonly WHITE='\033[37m'
readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly MAGENTA='\033[35m'
readonly CYAN='\033[36m'
readonly GRAY='\033[90m'
readonly LRED='\033[91m'
readonly LGREEN='\033[92m'
readonly LYELLOW='\033[93m'
readonly LBLUE='\033[94m'
readonly LMAGENTA='\033[95m'
readonly LCYAN='\033[96m'
readonly LWHITE='\033[97m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

readonly VERSION="${VERSION:-N/A}"

readonly AUTHORSTRING="${DIM}by ${LGREEN}e${LYELLOW}a${LMAGENTA}a${LBLUE}n${LGREEN}n${LYELLOW}i${LMAGENTA}s${LBLUE}t${NC}"

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
                                ${AUTHORSTRING}
                                     ${GRAY}v${VERSION:-N/A}
"
  echo -e "${NC}"
}

# -----------------------------------------------------------------------------
# Logging and input helpers (prompts/errors to stderr for command substitution)
# -----------------------------------------------------------------------------
log_info()  { echo -e "${LCYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${LGREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${LYELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${LRED}[x]${NC} $1"; }
log_ask()   { echo -e "${LBLUE}[?]${NC} $1"; }

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
  [[ -f "$HOME/minidite-version" ]] && sudo cp "$HOME/minidite-version" /etc/minidite-version 2>/dev/null || true
  log_ok "Configs installed"
  return 0
}

configure_sshd_minidite() {
  local cfg="/etc/ssh/sshd_config"
  local drop="/etc/ssh/sshd_config.d/90-minidite.conf"
  # Use drop-in if sshd supports it, otherwise append to main config
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    sudo tee "$drop" >/dev/null <<'SSHCFG'
# minidite hardening
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
Compression yes
X11Forwarding no
MaxAuthTries 3
SSHCFG
  else
    sudo grep -q '# minidite' "$cfg" 2>/dev/null || \
      printf '\n# minidite hardening\nPermitRootLogin no\nPubkeyAuthentication yes\nClientAliveInterval 60\nClientAliveCountMax 3\nTCPKeepAlive yes\nCompression yes\nX11Forwarding no\nMaxAuthTries 3\n' | sudo tee -a "$cfg" >/dev/null
  fi
}

configure_sshd_disable_password() {
  local drop="/etc/ssh/sshd_config.d/91-minidite-nopasswd.conf"
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    sudo tee "$drop" >/dev/null <<'SSHCFG'
# minidite: password auth disabled (key-only access)
PasswordAuthentication no
KbdInteractiveAuthentication no
SSHCFG
  else
    sudo grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null || \
      printf '\n# minidite: key-only\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
}

podman_post_install() {
  sudo mkdir -p /etc/containers/registries.conf.d
  [[ ! -f /etc/containers/registries.conf.d/10-unqualified-search-registries.conf ]] && \
    echo 'unqualified-search-registries = ["docker.io"]' | sudo tee /etc/containers/registries.conf.d/10-unqualified-search-registries.conf >/dev/null
  grep -q "^$(whoami):" /etc/subuid 2>/dev/null || sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)" 2>/dev/null
  systemctl --user enable --now podman.socket 2>/dev/null && log_ok "Podman socket enabled" || log_warn "Enable podman.socket manually if needed"
}

# =============================================================================
# Phase 1: Collect state and all user decisions
# =============================================================================
clear
show_logo
echo -e "  ${BOLD}${LYELLOW}minidite${NC}  ${GRAY}-- setup packages and configs${NC}"
echo -e "  ${GRAY}First you choose; then all actions run.${NC}"
echo ""

# Precompute state (no prompts)
installed_pkgs=()
missing_pkgs=()
for p in "${RECOMMENDED_PACKAGES[@]}"; do
  pacman -Q "$p" &>/dev/null && installed_pkgs+=("$p") || missing_pkgs+=("$p")
done
installed_count=${#installed_pkgs[@]}
missing_count=${#missing_pkgs[@]}
total=${#RECOMMENDED_PACKAGES[@]}
config_already=0
[[ -f "$HOME/.bashrc" ]] && grep -q 'minidite' "$HOME/.bashrc" 2>/dev/null && config_already=1
openssh_installed=0
pacman -Q openssh &>/dev/null && openssh_installed=1
has_key=0
has_auth=0
[[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]] && has_key=1
[[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]] && has_auth=1
docker_installed=0
pacman -Q docker &>/dev/null && docker_installed=1
podman_installed=0
pacman -Q podman &>/dev/null && podman_installed=1
omp_installed=0
command -v oh-my-posh &>/dev/null && omp_installed=1

# ---- Decisions: packages ----
log_info "Packages (${installed_count}/${total} installed, ${missing_count} missing)"
[[ $missing_count -gt 0 ]] && echo -e "  ${DIM}Missing: ${missing_pkgs[*]}${NC}"
if [[ $installed_count -eq 0 ]]; then
  echo "  1) Install missing  4) Skip"
  CHOICE_PKGS=$(read_choice "Choice (1 or 4): " "1" "4")
elif [[ $missing_count -gt 0 ]]; then
  echo "  1) Install missing  2) Update installed  3) Update installed and install missing  4) Skip"
  CHOICE_PKGS=$(read_choice "Choice (1-4): " "1" "2" "3" "4")
else
  echo "  1) Update installed  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && CHOICE_PKGS="2" || CHOICE_PKGS="4"
fi
echo ""

# ---- Decisions: config ----
log_info "Config files from repo"
if [[ $config_already -eq 1 ]]; then
  CONFIG_DO=$(read_yes_no "Configs already present. Overwrite? (yes/no): ")
else
  CONFIG_DO=$(read_yes_no "Download and install config files? (yes/no): ")
fi
echo ""

# ---- Decisions: Oh My Posh ----
log_info "Oh My Posh (prompt theme)"
if [[ $omp_installed -eq 1 ]]; then
  echo "  1) Update  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_OMP="yes" || INST_OMP="no"
else
  echo "  1) Install  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_OMP="yes" || INST_OMP="no"
fi
echo ""

# ---- Decisions: OpenSSH ----
log_info "OpenSSH server"
if [[ $openssh_installed -eq 1 ]]; then
  echo "  1) Update and ensure configured  2) Skip"
  CHOICE_OPENSSH=$(read_choice "Choice (1-2): " "1" "2")
else
  echo "  1) Install  2) Skip"
  CHOICE_OPENSSH=$(read_choice "Choice (1-2): " "1" "2")
fi
echo ""

# ---- Decisions: SSH keys ----
log_info "SSH keys (server key pair for outgoing connections)"
if [[ $has_key -eq 1 ]]; then
  GEN_SSH_KEY="no"
  log_ok "Server key already exists"
else
  GEN_SSH_KEY=$(read_yes_no "Generate server SSH key pair? (yes/no): ")
fi
echo ""

# ---- Decisions: SSH authorized client key ----
log_info "SSH client access (add your PC's public key for remote login)"
if [[ $has_auth -eq 1 ]]; then
  ADD_CLIENT_KEY="no"
  log_ok "authorized_keys already has entries"
  echo -e "  ${DIM}To add more keys later: paste into ~/.ssh/authorized_keys${NC}"
else
  echo -e "  ${DIM}To SSH without password, your CLIENT PC's public key must be on this server.${NC}"
  echo -e "  ${DIM}On your PC run: ${YELLOW}cat ~/.ssh/id_ed25519.pub${DIM} then paste it here.${NC}"
  echo -e "  ${DIM}If you skip now, you can add it later from your PC with:${NC}"
  echo -e "  ${YELLOW}ssh-copy-id $(whoami)@<server-ip>${NC}"
  ADD_CLIENT_KEY=$(read_yes_no "Add a client public key now? (yes/no): ")
fi
echo ""

# ---- Decisions: Disable SSH password auth ----
log_info "SSH password authentication"
nopasswd_already=0
[[ -f /etc/ssh/sshd_config.d/91-minidite-nopasswd.conf ]] && nopasswd_already=1
grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null && nopasswd_already=1
if [[ $nopasswd_already -eq 1 ]]; then
  DISABLE_SSH_PASS="no"
  log_ok "Password auth already disabled"
elif [[ $has_auth -eq 0 && "$ADD_CLIENT_KEY" != "yes" ]]; then
  DISABLE_SSH_PASS="no"
  log_info "Skipped (no client key in authorized_keys yet)"
  echo -e "  ${DIM}After adding your client key, run: ${YELLOW}ssh-lockdown${DIM} to disable passwords.${NC}"
else
  echo -e "  ${YELLOW}WARNING:${NC} Only answer yes if you are sure your client key is working."
  echo -e "  ${DIM}You can do this later with: ${YELLOW}ssh-lockdown${NC}"
  DISABLE_SSH_PASS=$(read_yes_no "Disable SSH password authentication? (yes/no): ")
fi
echo ""

# ---- Decisions: Docker ----
log_info "Docker"
if [[ $docker_installed -eq 1 ]]; then
  echo "  1) Update  2) Skip"
  CHOICE_DOCKER=$(read_choice "Choice (1-2): " "1" "2")
else
  echo "  1) Install  2) Skip"
  CHOICE_DOCKER=$(read_choice "Choice (1-2): " "1" "2")
fi
echo ""

# ---- Decisions: Podman ----
log_info "Podman"
if [[ $podman_installed -eq 1 ]]; then
  echo "  1) Update  2) Skip"
  CHOICE_PODMAN=$(read_choice "Choice (1-2): " "1" "2")
else
  echo "  1) Install  2) Skip"
  CHOICE_PODMAN=$(read_choice "Choice (1-2): " "1" "2")
fi
echo ""

# ---- Decisions: Lazydocker (only if Docker or Podman will be present) ----
will_have_container=0
[[ $docker_installed -eq 1 || "$CHOICE_DOCKER" == "1" ]] && will_have_container=1
[[ $podman_installed -eq 1 || "$CHOICE_PODMAN" == "1" ]] && will_have_container=1
lazydocker_installed=0
command -v lazydocker &>/dev/null && lazydocker_installed=1
[[ -x "$HOME/.local/bin/lazydocker" ]] && lazydocker_installed=1
log_info "Lazydocker (TUI for Docker/Podman)"
if [[ $will_have_container -eq 1 ]]; then
  if [[ $lazydocker_installed -eq 1 ]]; then
    echo "  1) Update  2) Skip"
  else
    echo "  1) Install  2) Skip"
  fi
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_LAZYDOCKER="yes" || INST_LAZYDOCKER="no"
else
  INST_LAZYDOCKER="no"
  log_info "Skipped (no Docker/Podman)"
fi
echo ""

# ---- Decisions: Snapper and Limine snapshot menu ----
has_snapper=0
command -v snapper &>/dev/null && has_snapper=1
has_snapshots_mount=0
[[ -d /.snapshots ]] && has_snapshots_mount=1
snapper_configured=0
snapper list-configs 2>/dev/null | grep -q "root" && snapper_configured=1

log_info "Snapper (Btrfs snapshots)"
if [[ $has_snapper -eq 1 && $has_snapshots_mount -eq 1 ]]; then
  if [[ $snapper_configured -eq 1 ]]; then
    CONF_SNAPPER="no"
    log_ok "Already configured"
  else
    CONF_SNAPPER=$(read_yes_no "Configure Snapper for root snapshots? (yes/no): ")
  fi
else
  CONF_SNAPPER="no"
  [[ $has_snapper -eq 0 ]] && log_info "Skipped (snapper not installed)"
  [[ $has_snapshots_mount -eq 0 ]] && log_info "Skipped (no /.snapshots)"
fi
echo ""

log_info "Limine snapshot menu (boot menu with snapshots)"
if [[ $has_snapper -eq 1 && $has_snapshots_mount -eq 1 ]]; then
  echo "  1) Install/configure  2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_LIMINE_MENU="yes" || INST_LIMINE_MENU="no"
else
  INST_LIMINE_MENU="no"
  log_info "Skipped (requires Snapper + /.snapshots)"
fi
echo ""

# ---- Confirm then run ----
proceed=$(read_yes_no "Apply all choices and run setup? (yes/no): ")
[[ "$proceed" != "yes" ]] && { log_info "Aborted."; exit 0; }
echo ""

# =============================================================================
# Phase 2: Execute all operations (no further prompts)
# =============================================================================
log_info "Phase 2: Executing..."
echo ""

# Summary tracking
declare -a SUMMARY_DONE=()
declare -a SUMMARY_SKIP=()
declare -a SUMMARY_WARN=()
s_done() { SUMMARY_DONE+=("$1"); }
s_skip() { SUMMARY_SKIP+=("$1"); }
s_warn() { SUMMARY_WARN+=("$1"); }

# ---- Step 1: Directories ----
log_info "Step 1/13: Directories"
for d in "${REQUIRED_DIRS[@]}"; do
  mkdir -p "$d" 2>/dev/null || { log_err "Cannot create $d"; exit 1; }
done
log_ok "Directories ready"
echo ""

# ---- Step 2: Packages ----
log_info "Step 2/13: Recommended CLI packages"
case "$CHOICE_PKGS" in
  1) [[ $missing_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${missing_pkgs[@]}" 2>/dev/null && { log_ok "Missing installed"; s_done "Packages: installed ${missing_pkgs[*]}"; } || { log_warn "Failed or nothing to do"; s_warn "Packages: install failed"; } ;;
  2) [[ $installed_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${installed_pkgs[@]}" 2>/dev/null && { log_ok "Updated"; s_done "Packages: updated"; } || { log_info "Nothing to update"; s_skip "Packages"; } ;;
  3)
    [[ $installed_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${installed_pkgs[@]}" 2>/dev/null || true
    [[ $missing_count -gt 0 ]] && sudo pacman -S --noconfirm --needed "${missing_pkgs[@]}" 2>/dev/null || true
    log_ok "Update and install done"; s_done "Packages: updated + installed"
    ;;
  4) log_info "Skipped"; s_skip "Packages" ;;
esac
echo ""

# ---- Step 3: Config ----
log_info "Step 3/13: Config files"
if [[ "$CONFIG_DO" == "yes" ]]; then
  download_configs && s_done "Config files downloaded" || { [[ $config_already -eq 1 ]] && s_warn "Config download partial" || exit 1; }
else
  log_info "Skipped"; s_skip "Config files"
fi
echo ""

# ---- Step 4: Oh My Posh ----
log_info "Step 4/13: Oh My Posh"
if [[ "$INST_OMP" == "yes" ]]; then
  if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Installed/updated"; s_done "Oh My Posh installed"
    mkdir -p "$CONFIG/oh-my-posh"
    curl -fsSL "${REPO_URL}/home/.config/oh-my-posh/theme.omp.json" -o "$CONFIG/oh-my-posh/theme.omp.json" 2>/dev/null || true
  else
    log_warn "Install failed"; s_warn "Oh My Posh install failed"
  fi
else
  log_info "Skipped"; s_skip "Oh My Posh"
fi
echo ""

# ---- Step 5: OpenSSH ----
log_info "Step 5/13: OpenSSH server"
_ssh_configured=0
if [[ "$CHOICE_OPENSSH" == "1" ]]; then
  if [[ $openssh_installed -eq 1 ]]; then
    sudo pacman -S --noconfirm --needed openssh 2>/dev/null || true
  else
    sudo pacman -S --noconfirm --needed openssh 2>/dev/null || { log_warn "Install failed"; s_warn "OpenSSH install failed"; }
  fi
  if pacman -Q openssh &>/dev/null; then
    configure_sshd_minidite
    sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "sshd enabled and hardened" || log_warn "sshd enable failed"
    _ssh_configured=1
    s_done "OpenSSH: installed, hardened (PermitRootLogin=no, MaxAuthTries=3)"
  fi
else
  log_info "Skipped"; s_skip "OpenSSH"
fi
echo ""

# ---- Step 6a: Server SSH key ----
log_info "Step 6/13: SSH keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ "$GEN_SSH_KEY" == "yes" ]]; then
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "minidite-$(whoami)@$(hostname)"
  chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
  log_ok "Server key pair generated"
  s_done "SSH: server ed25519 key generated"
elif [[ $has_key -eq 1 ]]; then
  log_ok "Server key already exists"
  s_done "SSH: server key already present"
else
  s_skip "SSH server key"
fi

# ---- Step 6b: Client key for remote access ----
if [[ "$ADD_CLIENT_KEY" == "yes" ]]; then
  echo ""
  echo -e "${BOLD}Paste your client's public key (one line, then press Enter):${NC}"
  read -r client_pubkey </dev/tty
  if [[ -n "$client_pubkey" ]]; then
    echo "$client_pubkey" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    log_ok "Client key added to authorized_keys"
    s_done "SSH: client public key added to authorized_keys"
  else
    log_warn "Empty input, skipped"
    s_warn "SSH: client key input was empty"
  fi
elif [[ $has_auth -eq 1 ]]; then
  s_done "SSH: authorized_keys already configured"
else
  s_skip "SSH client key"
fi

# ---- Step 6c: Disable password authentication ----
if [[ "$DISABLE_SSH_PASS" == "yes" ]]; then
  auth_count=$(wc -l < "$HOME/.ssh/authorized_keys" 2>/dev/null || echo 0)
  if [[ "$auth_count" -gt 0 ]]; then
    configure_sshd_disable_password
    sudo systemctl reload sshd.service 2>/dev/null || true
    log_ok "Password authentication disabled (key-only access)"
    s_done "SSH: password auth disabled (key-only)"
  else
    log_warn "No keys in authorized_keys! Keeping password auth enabled to avoid lockout."
    s_warn "SSH: password auth NOT disabled (no client keys found)"
  fi
else
  s_skip "SSH: password auth remains enabled"
fi
echo ""

# ---- Step 7: Docker ----
log_info "Step 7/13: Docker"
if [[ "$CHOICE_DOCKER" == "1" ]]; then
  if sudo pacman -S --noconfirm --needed docker docker-compose 2>/dev/null; then
    sudo systemctl enable --now docker.service 2>/dev/null
    sudo usermod -aG docker "$(whoami)" 2>/dev/null
    log_ok "Docker installed/updated"; s_done "Docker: installed, $(whoami) in docker group"
    docker_installed=1
  else
    log_warn "Install failed"; s_warn "Docker install failed"
  fi
else
  log_info "Skipped"; s_skip "Docker"
fi
echo ""

# ---- Step 8: Podman ----
log_info "Step 8/13: Podman"
if [[ "$CHOICE_PODMAN" == "1" ]]; then
  if sudo pacman -S --noconfirm --needed podman 2>/dev/null; then
    log_ok "Podman installed/updated"; s_done "Podman: installed"
    podman_post_install
    podman_installed=1
  else
    log_warn "Install failed"; s_warn "Podman install failed"
  fi
else
  log_info "Skipped"; s_skip "Podman"
fi
echo ""

# ---- Step 9: Lazydocker ----
log_info "Step 9/13: Lazydocker"
if [[ "$INST_LAZYDOCKER" == "yes" ]]; then
  if curl -sSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Installed/updated to ~/.local/bin"; s_done "Lazydocker: installed"
  else
    log_warn "Install failed"; s_warn "Lazydocker install failed"
  fi
else
  log_info "Skipped"; s_skip "Lazydocker"
fi
echo ""

# ---- Step 10: Snapper configuration ----
log_info "Step 10/13: Snapper configuration"
if [[ "$CONF_SNAPPER" == "yes" ]]; then
  sudo umount /.snapshots 2>/dev/null || true
  sudo rmdir /.snapshots 2>/dev/null || true
  if sudo snapper -c root create-config /; then
    sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
    sudo mkdir -p /.snapshots
    sudo mount /.snapshots
    sudo chmod 750 /.snapshots
    sudo sed -i \
      's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/;
       s/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/;
       s/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="0"/;
       s/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/;
       s/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/;
       s/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/;
       s/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/;
       s/^NUMBER_LIMIT=.*/NUMBER_LIMIT="5"/;
       s/^NUMBER_MIN_AGE=.*/NUMBER_MIN_AGE="0"/' \
      /etc/snapper/configs/root
    sudo btrfs quota enable / 2>/dev/null || true
    sudo systemctl enable --now snapper-cleanup.timer 2>/dev/null || true
    # Daily snapshot via cron (uses number cleanup type so NUMBER_LIMIT=5 applies)
    (sudo crontab -l 2>/dev/null | grep -v 'snapper.*daily'; echo "0 4 * * * /usr/bin/snapper -c root create -c number --description \"daily auto\"") | sudo crontab - 2>/dev/null || true
    log_ok "Snapper configured (max 5 snapshots, daily auto at 4am)"
    if sudo snapper -c root create -c number --description "setup-test $(date +%Y-%m-%d_%H:%M)"; then
      log_ok "Test snapshot created"; s_done "Snapper: configured + test snapshot OK"
    else
      log_warn "Test snapshot failed"; s_warn "Snapper: configured but test snapshot failed"
    fi
  else
    sudo mkdir -p /.snapshots
    sudo mount /.snapshots 2>/dev/null || true
    log_warn "Snapper create-config failed"; s_warn "Snapper: create-config failed"
  fi
else
  log_info "Skipped"; s_skip "Snapper"
fi
echo ""

# ---- Step 11: Limine snapshot menu ----
log_info "Step 11/13: Limine snapshot menu"
if [[ "$INST_LIMINE_MENU" == "yes" ]]; then
  LIMINE_SCRIPT='/usr/local/bin/limine-snapper-menu.sh'
  sudo tee "$LIMINE_SCRIPT" >/dev/null <<'LIMINE_SCRIPT_END'
#!/bin/bash
# Regenerate Limine boot menu: Minidite tree + snapper snapshots (read-only recovery)
set -e
ROOT_UUID=$(findmnt -n -o UUID /)
CFG="/boot/EFI/arch-limine/limine.conf"
mkdir -p "$(dirname "$CFG")"

VERSION=$(cat /etc/minidite-version 2>/dev/null || cat /home/*/minidite-version 2>/dev/null | head -1 || true)
BRANDING="Minidite Bootloader"
[[ -n "$VERSION" ]] && BRANDING="Minidite v${VERSION}"

SNAP_DIR="/.snapshots"

# Collect snapshot entries (process substitution keeps vars in current shell)
SNAP_TMP=$(mktemp)
snap_count=0
while IFS='|' read -r num type desc date; do
  num=$(echo "$num" | tr -d ' ')
  type=$(echo "$type" | tr -d ' ')
  desc=$(echo "$desc" | sed 's/^ *//;s/ *$//')
  date=$(echo "$date" | sed 's/^ *//;s/ *$//')
  [[ "$type" != "single" ]] && continue
  [[ -z "$num" || "$num" == "0" ]] && continue
  [[ -d "${SNAP_DIR}/${num}/snapshot" ]] || continue
  LABEL="#${num}"
  [[ -n "$desc" ]] && LABEL="#${num} ${desc}"
  [[ -n "$date" ]] && LABEL="${LABEL} (${date})"
  echo "/// ${LABEL}" >> "$SNAP_TMP"
  echo "    protocol: linux" >> "$SNAP_TMP"
  echo "    path: boot():/vmlinuz-linux" >> "$SNAP_TMP"
  echo "    cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@snapshots/${num}/snapshot ro" >> "$SNAP_TMP"
  echo "    module_path: boot():/initramfs-linux.img" >> "$SNAP_TMP"
  snap_count=$((snap_count + 1))
done < <(snapper -c root list --columns number,type,description,date 2>/dev/null | tail -n +3)

# Write full config: theme + tree menu
{
  echo "timeout: 5"
  echo "default_entry: 2"
  echo "interface_branding: ${BRANDING}"
  echo "interface_branding_color: 6"
  echo "interface_help_color: 6"
  echo "hash_mismatch_panic: no"
  echo ""
  echo "term_background: 000000"
  echo "backdrop: 000000"
  echo "term_foreground: f0e0a0"
  echo "term_foreground_bright: f8ecb8"
  echo "term_background_bright: 141410"
  echo "term_palette: 0c0c0c;e06060;70c870;f0e0a0;5080c0;a070c0;56c8d8;a8a898"
  echo "term_palette_bright: 2a2a28;f08080;90e890;f8ecb8;70a0e0;c090e0;70e8f0;d0d0c0"
  echo ""
  echo "/+ Minidite"
  echo "// linux"
  echo "    protocol: linux"
  echo "    path: boot():/vmlinuz-linux"
  echo "    cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw"
  echo "    module_path: boot():/initramfs-linux.img"
  if [[ $snap_count -gt 0 ]]; then
    echo ""
    echo "//+ Snapshots"
    cat "$SNAP_TMP"
  fi
} > "$CFG"
rm -f "$SNAP_TMP"
cp "$CFG" /boot/limine.conf
echo "Limine menu updated: $((snap_count + 1)) entries"
LIMINE_SCRIPT_END
  sudo chmod +x "$LIMINE_SCRIPT"
  (sudo crontab -l 2>/dev/null | grep -v limine-snapper-menu; echo "0 3 * * * /usr/local/bin/limine-snapper-menu.sh") | sudo crontab - 2>/dev/null && log_ok "Script and daily cron (3am) installed" || log_ok "Script installed"
  sudo "$LIMINE_SCRIPT" && { log_ok "Menu updated"; s_done "Limine snapshot menu: installed + cron"; } || { log_warn "First menu run failed"; s_warn "Limine menu: script installed, first run failed"; }
else
  log_info "Skipped"; s_skip "Limine snapshot menu"
fi
echo ""

# ---- Step 12: fzf ----
log_info "Step 12/13: fzf"
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.bash ]] && cp /usr/share/fzf/key-bindings.bash "$CONFIG/fzf/" 2>/dev/null
  [[ -f /usr/share/fzf/completion.bash ]]   && cp /usr/share/fzf/completion.bash "$CONFIG/fzf/" 2>/dev/null
  log_ok "Bindings copied"; s_done "fzf: key bindings configured"
else
  log_info "fzf not installed, skipped"; s_skip "fzf"
fi
echo ""

# ---- Step 13: Cleanup ----
log_info "Step 13/13: Cleanup and optimizations"
sudo pacman -Scc --noconfirm 2>/dev/null && log_ok "Pacman cache cleared" || true
orphans=$(pacman -Qdtq 2>/dev/null || true)
[[ -n "$orphans" ]] && sudo pacman -Rns --noconfirm $orphans 2>/dev/null && log_ok "Orphans removed" || true
sudo systemctl enable fstrim.timer 2>/dev/null && log_ok "fstrim.timer enabled" || true
pacman -Q pacman-contrib &>/dev/null && sudo systemctl enable paccache.timer 2>/dev/null && log_ok "paccache.timer enabled" || true
s_done "Cleanup: cache cleared, timers enabled"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo -e "${BOLD}${LCYAN}=== Setup Summary ===${NC}"
echo ""
if [[ ${#SUMMARY_DONE[@]} -gt 0 ]]; then
  echo -e "${LGREEN}${BOLD}Completed:${NC}"
  for item in "${SUMMARY_DONE[@]}"; do
    echo -e "  ${LGREEN}+${NC} ${item}"
  done
  echo ""
fi
if [[ ${#SUMMARY_WARN[@]} -gt 0 ]]; then
  echo -e "${LYELLOW}${BOLD}Warnings:${NC}"
  for item in "${SUMMARY_WARN[@]}"; do
    echo -e "  ${LYELLOW}!${NC} ${item}"
  done
  echo ""
fi
if [[ ${#SUMMARY_SKIP[@]} -gt 0 ]]; then
  echo -e "${GRAY}Skipped:${NC}"
  for item in "${SUMMARY_SKIP[@]}"; do
    echo -e "  ${GRAY}-${NC} ${GRAY}${item}${NC}"
  done
  echo ""
fi
log_ok "Setup complete."
echo ""
echo -e "  ${BOLD}${LWHITE}Next:${NC}"
echo -e "    ${LYELLOW}source ~/.bashrc${NC}   or   ${LYELLOW}exec bash${NC}"
echo -e "    Set terminal font to a ${BOLD}Nerd Font${NC} for icons."
echo -e "    Type ${LYELLOW}show-help${NC} for command reference."
echo ""
