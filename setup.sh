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
# Phase 1: Collect state and all user decisions
# =============================================================================
clear
show_logo
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- setup packages and configs${NC}"
echo -e "  ${DIM}First you choose; then all actions run.${NC}"
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
log_info "SSH keys"
if [[ $has_key -eq 1 && $has_auth -eq 1 ]]; then
  GEN_SSH_KEY="no"
  ADD_SSH_KEY="no"
  log_ok "Already configured"
else
  if [[ $has_key -eq 0 ]]; then
    GEN_SSH_KEY=$(read_yes_no "Generate SSH key pair? (yes/no): ")
    ADD_SSH_KEY="no"
  else
    GEN_SSH_KEY="no"
    [[ $has_auth -eq 0 ]] && ADD_SSH_KEY=$(read_yes_no "Add existing public key to authorized_keys? (yes/no): ") || ADD_SSH_KEY="no"
  fi
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

# ---- Step 3: Config ----
log_info "Step 3/13: Config files"
if [[ "$CONFIG_DO" == "yes" ]]; then
  download_configs || { [[ $config_already -eq 1 ]] || exit 1; }
else
  log_info "Skipped"
fi
echo ""

# ---- Step 4: Oh My Posh ----
log_info "Step 4/13: Oh My Posh"
if [[ "$INST_OMP" == "yes" ]]; then
  if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Installed/updated"
    mkdir -p "$CONFIG/oh-my-posh"
    curl -fsSL "${REPO_URL}/home/.config/oh-my-posh/theme.omp.json" -o "$CONFIG/oh-my-posh/theme.omp.json" 2>/dev/null && log_ok "Theme copied" || true
  else
    log_warn "Install failed"
  fi
else
  log_info "Skipped"
fi
echo ""

# ---- Step 5: OpenSSH ----
log_info "Step 5/13: OpenSSH server"
if [[ $openssh_installed -eq 1 ]]; then
  [[ "$CHOICE_OPENSSH" == "1" ]] && { sudo pacman -S -u --noconfirm openssh 2>/dev/null || true; configure_sshd_minidite; sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "sshd enabled" || true; } || log_info "Skipped"
else
  if [[ "$CHOICE_OPENSSH" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed openssh 2>/dev/null; then
      configure_sshd_minidite
      sudo systemctl enable --now sshd.service 2>/dev/null && log_ok "OpenSSH installed and sshd enabled" || log_warn "sshd enable failed"
    else
      log_warn "Install failed"
    fi
  else
    log_info "Skipped"
  fi
fi
echo ""

# ---- Step 6: SSH keys ----
log_info "Step 6/13: SSH keys"
if [[ $has_key -eq 1 && $has_auth -eq 1 ]]; then
  log_ok "Already configured"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [[ "$GEN_SSH_KEY" == "yes" ]]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "minidite"
    chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
    cat "$HOME/.ssh/id_ed25519.pub" >> "$HOME/.ssh/authorized_keys" 2>/dev/null
    chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
    log_ok "Key created and added to authorized_keys"
    echo ""; echo -e "${BOLD}Public key:${NC}"; cat "$HOME/.ssh/id_ed25519.pub"; echo ""
  elif [[ "$ADD_SSH_KEY" == "yes" ]]; then
    pub=$(ls "$HOME/.ssh/"*.pub 2>/dev/null | head -1)
    if [[ -n "$pub" ]]; then
      cat "$pub" >> "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      log_ok "Added to authorized_keys"
    fi
  fi
fi
echo ""

# ---- Step 7: Docker ----
log_info "Step 7/13: Docker"
if [[ $docker_installed -eq 1 ]]; then
  [[ "$CHOICE_DOCKER" == "1" ]] && { sudo pacman -S -u --noconfirm docker docker-compose 2>/dev/null || true; sudo systemctl enable --now docker.service 2>/dev/null; sudo usermod -aG docker "$(whoami)" 2>/dev/null; log_ok "Updated"; } || log_info "Skipped"
else
  if [[ "$CHOICE_DOCKER" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed docker docker-compose 2>/dev/null; then
      sudo systemctl enable --now docker.service 2>/dev/null
      sudo usermod -aG docker "$(whoami)" 2>/dev/null
      log_ok "Docker installed (log out and back in for group)"
      docker_installed=1
    else
      log_warn "Install failed"
    fi
  else
    log_info "Skipped"
  fi
fi
echo ""

# ---- Step 8: Podman ----
log_info "Step 8/13: Podman"
if [[ $podman_installed -eq 1 ]]; then
  [[ "$CHOICE_PODMAN" == "1" ]] && { sudo pacman -S -u --noconfirm podman 2>/dev/null || true; log_ok "Updated"; } || log_info "Skipped"
else
  if [[ "$CHOICE_PODMAN" == "1" ]]; then
    if sudo pacman -S --noconfirm --needed podman 2>/dev/null; then
      log_ok "Podman installed"
      podman_post_install
      podman_installed=1
    else
      log_warn "Install failed"
    fi
  else
    log_info "Skipped"
  fi
fi
echo ""

# ---- Step 9: Lazydocker ----
log_info "Step 9/13: Lazydocker"
if [[ "$INST_LAZYDOCKER" == "yes" ]]; then
  curl -sSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null && log_ok "Installed/updated to ~/.local/bin" || log_warn "Install failed"
else
  log_info "Skipped"
fi
echo ""

# ---- Step 10: Snapper configuration ----
log_info "Step 10/13: Snapper configuration"
if [[ "$CONF_SNAPPER" == "yes" ]]; then
  # Arch Wiki approach: snapper create-config creates a nested .snapshots subvolume,
  # but we already have @snapshots mounted at /.snapshots from install.sh.
  # Fix: unmount, let snapper create its config, delete its subvolume, remount ours.
  sudo umount /.snapshots 2>/dev/null || true
  sudo rmdir /.snapshots 2>/dev/null || true
  if sudo snapper -c root create-config /; then
    sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
    sudo mkdir -p /.snapshots
    sudo mount /.snapshots
    sudo chmod 750 /.snapshots
    # Tune snapper limits
    sudo sed -i \
      's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/;
       s/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="5"/;
       s/^NUMBER_LIMIT=.*/NUMBER_LIMIT="5-10"/' \
      /etc/snapper/configs/root
    # Enable btrfs quota for space-aware cleanup
    sudo btrfs quota enable / 2>/dev/null || true
    log_ok "Snapper configured"
    # Verify with a test snapshot
    if sudo snapper -c root create --description "setup-test $(date +%Y-%m-%d_%H:%M)"; then
      log_ok "Test snapshot created (verify with: sudo snapper -c root list)"
    else
      log_warn "Test snapshot failed"
    fi
  else
    sudo mkdir -p /.snapshots
    sudo mount /.snapshots 2>/dev/null || true
    log_warn "Snapper create-config failed"
  fi
else
  log_info "Skipped"
fi
echo ""

# ---- Step 11: Limine snapshot menu ----
log_info "Step 11/13: Limine snapshot menu"
if [[ "$INST_LIMINE_MENU" == "yes" ]]; then
  LIMINE_SCRIPT='/usr/local/bin/limine-snapper-menu.sh'
  sudo tee "$LIMINE_SCRIPT" >/dev/null <<'LIMINE_SCRIPT_END'
#!/bin/bash
# Regenerate Limine boot menu: current root + snapper snapshots (read-only recovery)
set -e
ROOT_UUID=$(findmnt -n -o UUID /)
CFG="/boot/EFI/arch-limine/limine.conf"
mkdir -p "$(dirname "$CFG")"

SNAP_BASE=$(snapper -c root get-config 2>/dev/null | grep SUBVOLUME | sed 's/.*= *//' || true)
[[ -z "$SNAP_BASE" ]] && SNAP_BASE="/.snapshots"

{
  echo "timeout: 5"
  echo ""
  echo "/Arch Linux"
  echo "    protocol: linux"
  echo "    path: boot():/vmlinuz-linux"
  echo "    cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw"
  echo "    module_path: boot():/initramfs-linux.img"

  # Snapshots: boot read-only for recovery/inspection; use snap-rollback to make permanent
  snapper -c root list --columns number,type,description,date 2>/dev/null | tail -n +3 | while IFS='|' read -r num type desc date; do
    num=$(echo "$num" | tr -d ' ')
    type=$(echo "$type" | tr -d ' ')
    desc=$(echo "$desc" | sed 's/^ *//;s/ *$//')
    date=$(echo "$date" | sed 's/^ *//;s/ *$//')
    [[ "$type" != "single" ]] && continue
    [[ -z "$num" || "$num" == "0" ]] && continue
    DIR="${SNAP_BASE}/${num}/snapshot"
    [[ -d "$DIR" ]] || continue
    SNAP_SUBVOL="@snapshots/${num}/snapshot"
    LABEL="#${num}"
    [[ -n "$desc" ]] && LABEL="#${num} ${desc}"
    [[ -n "$date" ]] && LABEL="${LABEL} (${date})"
    echo ""
    echo "/Snapshot ${LABEL}"
    echo "    protocol: linux"
    echo "    path: boot():/vmlinuz-linux"
    echo "    cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=${SNAP_SUBVOL} ro"
    echo "    module_path: boot():/initramfs-linux.img"
  done
} > "$CFG"
cp "$CFG" /boot/limine.conf
echo "Limine menu updated: $(grep -c '^/' "$CFG") entries"
LIMINE_SCRIPT_END
  sudo chmod +x "$LIMINE_SCRIPT"
  (sudo crontab -l 2>/dev/null | grep -v limine-snapper-menu; echo "0 3 * * * /usr/local/bin/limine-snapper-menu.sh") | sudo crontab - 2>/dev/null && log_ok "Script and daily cron (3am) installed" || log_ok "Script installed"
  sudo "$LIMINE_SCRIPT" 2>/dev/null && log_ok "Menu updated" || log_warn "First menu run failed (run snap or wait for snapshot)"
else
  log_info "Skipped"
fi
echo ""

# ---- Step 12: fzf ----
log_info "Step 12/13: fzf"
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.bash ]] && cp /usr/share/fzf/key-bindings.bash "$CONFIG/fzf/" 2>/dev/null
  [[ -f /usr/share/fzf/completion.bash ]]   && cp /usr/share/fzf/completion.bash "$CONFIG/fzf/" 2>/dev/null
  log_ok "Bindings copied"
else
  log_info "fzf not installed, skipped"
fi
echo ""

# ---- Step 13: Cleanup ----
log_info "Step 13/13: Cleanup and optimizations"
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
