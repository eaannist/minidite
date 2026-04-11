#!/bin/bash

# =============================================================================
# minidite - Post-install setup: packages, configs, SSH, containers (interactive)
# =============================================================================
# Run as normal user after first login (after install.sh and reboot).
# Usage: curl -fsSL /setup | bash
# Uses sudo when needed. Reads from /dev/tty for interactive prompts.
# =============================================================================

set -euo pipefail

SETUP_LOG="${SETUP_LOG:-setup.log}"
[[ "$SETUP_LOG" != /* ]] && SETUP_LOG="$(pwd)/$SETUP_LOG"
exec > >(tee "$SETUP_LOG") 2>&1
echo "=== Minidite setup started $(date -Iseconds) ==="

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

readonly AUTHORSTRING="${LGREEN}e${LYELLOW}a${LMAGENTA}a${LRED}n${LGREEN}n${LYELLOW}i${LMAGENTA}s${LRED}t${NC}"

# Header logo

show_logo() {
  echo -e "${CYAN}"
  echo -e "
  ██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄
  ██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄ 
  ██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄

  ${AUTHORSTRING}                             ${GRAY}v${VERSION:-N/A}
"
  echo -e "${NC}"
  echo -e "  ${GREEN}#Setup${NC}"
}

# -----------------------------------------------------------------------------
# Config variables
# -----------------------------------------------------------------------------

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/eaannist/minidite/main}"
HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
CONFIG="${HOME}/.config"

CONFIG_FILES=(
  "home/.bashrc:$HOME/.bashrc:1"
  "home/.config/oh-my-posh/theme.omp.json:$CONFIG/oh-my-posh/theme.omp.json:0"
  "home/.config/micro/settings.json:$CONFIG/micro/settings.json:0"
  "home/.config/micro/colorschemes/custom.micro:$CONFIG/micro/colorschemes/custom.micro:0"
  "home/.config/fastfetch/config.jsonc:$CONFIG/fastfetch/config.jsonc:0"
  "home/.config/fastfetch/minidite.txt:$CONFIG/fastfetch/minidite.txt:0"
  "home/minidite-version:$HOME/minidite-version:0"
  "home/.config/tmux/tmux.conf:$CONFIG/tmux/tmux.conf:0"
)

REQUIRED_DIRS=(
  "$CONFIG/oh-my-posh"
  "$CONFIG/micro"
  "$CONFIG/micro/colorschemes"
  "$CONFIG/fastfetch"
  "$CONFIG/tmux"
  "$CONFIG/fzf"
  "$HOME/.local/bin"
  "$HOME/.cache/bash"
)

RECOMMENDED_PACKAGES=(micro btop zoxide fzf ripgrep eza unzip tree tmux ttf-firacode-nerd fastfetch git)

# Persisted after a successful run; presence switches to update mode
SETUP_STATE_FILE="${HOME}/minidite-setup-data"
SETUP_STATE_VERSION=1

# /etc/default/limine — @@CMDLINE@@ is replaced at runtime in Step 11
LIMINE_DEFAULT_CONF=$(cat <<EOF
TARGET_OS_NAME="Minidite"
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="@@CMDLINE@@"
FIND_BOOTLOADERS=no
ENABLE_LIMINE_FALLBACK=no
ENABLE_UKI=yes
CUSTOM_UKI_NAME="minidite"
ROOT_SUBVOLUME_PATH="/@"
ROOT_SNAPSHOTS_PATH="/@snapshots"
BOOT_ORDER="*, *fallback, Snapshots"
MAX_SNAPSHOT_ENTRIES=5
SNAPSHOT_FORMAT_CHOICE=5
EOF
)

# /boot/limine.conf — base theme only, no manual entries
# limine-snapper-sync will inject /+Minidite, //linux, //Snapshots
LIMINE_LIMINE_CONF=$(cat <<EOF
### https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
timeout: 3
default_entry: 2
interface_branding: Minidite v${VERSION}
interface_branding_color: 6
interface_help_color: 6
hash_mismatch_panic: no

term_background: 000000
backdrop: 000000
term_foreground: f0e0a0
term_foreground_bright: f8ecb8
term_background_bright: 141410
term_palette: 0c0c0c;e06060;70c870;f0e0a0;5080c0;a070c0;56c8d8;a8a898
term_palette_bright: 2a2a28;f08080;90e890;f8ecb8;70a0e0;c090e0;70e8f0;d0d0c0
EOF
)

# /etc/snapper/configs/root
SNAPPER_CONFIG=$(cat <<'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
TIMELINE_CREATE="yes"
TIMELINE_CREATE_AT_START="no"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="86400"
TIMELINE_LIMIT_HOURLY="0"
TIMELINE_LIMIT_DAILY="5"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
NUMBER_CLEANUP="yes"
NUMBER_LIMIT="3"
NUMBER_LIMIT_IMPORTANT="3"
NUMBER_MIN_AGE="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF
)

# -----------------------------------------------------------------------------
# Logging and input helpers
# -----------------------------------------------------------------------------

log_info() { echo -e "${LCYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${LGREEN}[+]${NC} $1"; }
log_warn() { echo -e "${LYELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${LRED}[x]${NC} $1"; }
log_ask()  { echo -e "${LBLUE}[?]${NC} $1"; }

read_choice() {
  local prompt="$1"
  shift
  local allowed=("$@")
  local choice
  while true; do
    log_ask "$prompt" >&2
    read -r choice </dev/tty
    choice=$(echo "$choice" | tr -d '[:space:]')
    for a in "${allowed[@]}"; do
      if [[ "$choice" == "$a" ]]; then echo "$choice"; return 0; fi
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
    choice=$(echo "$choice" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [[ "$choice" == "yes" ]] && { echo "yes"; return 0; }
    [[ "$choice" == "no"  ]] && { echo "no";  return 0; }
    log_err "Invalid. Enter yes or no." >&2
  done
}

# -----------------------------------------------------------------------------
# Summary on exit (trap ensures it runs even on early exit)
# -----------------------------------------------------------------------------

show_summary() {
  [[ "${SHOW_SUMMARY:-0}" -eq 1 ]] || return 0
  echo ""
  echo -e "${BOLD}${LCYAN}=== Setup Summary ===${NC}"
  echo ""
  if [[ ${#SUMMARY_DONE[@]} -gt 0 ]]; then
    echo -e "${LGREEN}${BOLD}Completed:${NC}"
    for item in "${SUMMARY_DONE[@]}"; do echo -e "  ${LGREEN}+${NC} ${item}"; done
    echo ""
  fi
  if [[ ${#SUMMARY_WARN[@]} -gt 0 ]]; then
    echo -e "${LYELLOW}${BOLD}Warnings:${NC}"
    for item in "${SUMMARY_WARN[@]}"; do echo -e "  ${LYELLOW}!${NC} ${item}"; done
    echo ""
  fi
  if [[ ${#SUMMARY_SKIP[@]} -gt 0 ]]; then
    echo -e "${GRAY}Skipped:${NC}"
    for item in "${SUMMARY_SKIP[@]}"; do echo -e "  ${GRAY}-${NC} ${GRAY}${item}${NC}"; done
    echo ""
  fi
  if [[ ${#SUMMARY_DONE[@]} -gt 0 || ${#SUMMARY_WARN[@]} -gt 0 || ${#SUMMARY_SKIP[@]} -gt 0 ]]; then
    log_ok "Setup complete."
    echo ""
    echo -e "  ${BOLD}${LWHITE}Next:${NC}"
    echo -e "  Run command ${YELLOW}exec bash${NC} to load the new configuration."
    echo -e "  Set terminal font to a ${RED}${BOLD}Nerd Font${NC} for icons."
    echo ""
  fi
  echo -e "  ${GRAY}Log: ${SETUP_LOG}${NC}"
}

declare -a SUMMARY_DONE=() SUMMARY_WARN=() SUMMARY_SKIP=()
SHOW_SUMMARY=1
trap show_summary EXIT


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
# Helpers
# -----------------------------------------------------------------------------

download_configs() {
  local entry src dest required
  for entry in "${CONFIG_FILES[@]}"; do
    IFS=: read -r src dest required <<< "$entry"
    if curl -fsSL "${REPO_URL}/${src}" -o "$dest" 2>/dev/null; then
      : # ok
    else
      [[ "$required" -eq 1 ]] && { log_err "Failed to download required file: $src"; touch "$dest"; return 1; }
      log_warn "Failed to download optional file: $src"
    fi
  done
  [[ -f "$HOME/minidite-version" ]] && sudo cp "$HOME/minidite-version" /etc/minidite-version 2>/dev/null || true
  log_ok "Configs installed"
  return 0
}

# Config tags: bashrc, version, omp, micro, fastfetch, tmux (lines: repo_path:dest:required)
get_config_tag_entries() {
  local tag="$1"
  case "$tag" in
    bashrc)    echo "home/.bashrc:$HOME/.bashrc:1" ;;
    version)   echo "home/minidite-version:$HOME/minidite-version:0" ;;
    omp)       echo "home/.config/oh-my-posh/theme.omp.json:$CONFIG/oh-my-posh/theme.omp.json:0" ;;
    micro)
      echo "home/.config/micro/settings.json:$CONFIG/micro/settings.json:0"
      echo "home/.config/micro/colorschemes/custom.micro:$CONFIG/micro/colorschemes/custom.micro:0"
      ;;
    fastfetch)
      echo "home/.config/fastfetch/config.jsonc:$CONFIG/fastfetch/config.jsonc:0"
      echo "home/.config/fastfetch/minidite.txt:$CONFIG/fastfetch/minidite.txt:0"
      ;;
    tmux)
      echo "home/.config/tmux/tmux.conf:$CONFIG/tmux/tmux.conf:0"
      echo "home/.config/tmux/tmux-help.sh:$CONFIG/tmux/tmux-help.sh:0"
      ;;
    *)         return 1 ;;
  esac
}

# Map a pacman package name to extra config tags (beyond bashrc/version)
pkg_to_config_tags() {
  case "$1" in
    micro)     echo micro ;;
    fastfetch) echo fastfetch ;;
    tmux)      echo tmux ;;
    *)         ;;
  esac
}

download_configs_by_tags() {
  local tag entry src dest required failed=0
  for tag in "$@"; do
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      IFS=: read -r src dest required <<< "$entry"
      if curl -fsSL "${REPO_URL}/${src}" -o "$dest" 2>/dev/null; then
        :
      else
        [[ "$required" -eq 1 ]] && { log_err "Failed to download required file: $src"; failed=1; }
        log_warn "Failed to download optional file: $src"
      fi
    done < <(get_config_tag_entries "$tag" 2>/dev/null || true)
  done
  [[ -f "$HOME/minidite-version" ]] && sudo cp "$HOME/minidite-version" /etc/minidite-version 2>/dev/null || true
  [[ $failed -eq 1 ]] && return 1
  log_ok "Config files downloaded"
  return 0
}

save_setup_state() {
  umask 077
  {
    echo "MINIDITE_SETUP_VERSION=${SETUP_STATE_VERSION}"
    echo "FIRST_RUN_DATE=${FIRST_RUN_DATE:-$(date -Iseconds)}"
    echo "LAST_RUN_DATE=$(date -Iseconds)"
  } > "$SETUP_STATE_FILE" 2>/dev/null || true
}

load_first_run_date() {
  FIRST_RUN_DATE=""
  [[ -f "$SETUP_STATE_FILE" ]] || return 0
  # shellcheck source=/dev/null
  source "$SETUP_STATE_FILE" 2>/dev/null || true
}

# Parse space-separated indices (1-based) into package names; validates against RECOMMENDED_PACKAGES
parse_pkg_indices() {
  local line="$1" i name
  SELECTED_PKGS=()
  for i in $line; do
    [[ "$i" =~ ^[0-9]+$ ]] || continue
    (( i >= 1 && i <= ${#RECOMMENDED_PACKAGES[@]} )) || continue
    name="${RECOMMENDED_PACKAGES[$((i - 1))]}"
    SELECTED_PKGS+=("$name")
  done
}

# Installed subset of RECOMMENDED_PACKAGES (names)
list_installed_recommended() {
  local p out=()
  for p in "${RECOMMENDED_PACKAGES[@]}"; do
    pacman -Q "$p" &>/dev/null && out+=("$p")
  done
  echo "${out[@]}"
}

# Deduplicate config tag names into global CONFIG_TAGS
dedupe_tags() {
  local t
  declare -A seen=()
  CONFIG_TAGS=()
  for t in "$@"; do
    [[ -z "$t" ]] && continue
    [[ ${seen[$t]+x} ]] && continue
    seen[$t]=1
    CONFIG_TAGS+=("$t")
  done
}

configure_sshd_minidite() {
  local cfg="/etc/ssh/sshd_config"
  local drop="/etc/ssh/sshd_config.d/90-minidite.conf"
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
      printf '\n# minidite hardening\nPermitRootLogin no\nPubkeyAuthentication yes\nClientAliveInterval 60\nClientAliveCountMax 3\nTCPKeepAlive yes\nCompression yes\nX11Forwarding no\nMaxAuthTries 3\n' \
        | sudo tee -a "$cfg" >/dev/null
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
      printf '\n# minidite: key-only\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
        | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
}

podman_post_install() {
  sudo mkdir -p /etc/containers/registries.conf.d
  [[ ! -f /etc/containers/registries.conf.d/10-unqualified-search-registries.conf ]] && \
    echo 'unqualified-search-registries = ["docker.io"]' \
      | sudo tee /etc/containers/registries.conf.d/10-unqualified-search-registries.conf >/dev/null
  grep -q "^$(whoami):" /etc/subuid 2>/dev/null || \
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)" 2>/dev/null
  systemctl --user enable --now podman.socket 2>/dev/null \
    && log_ok "Podman socket enabled" \
    || log_warn "Enable podman.socket manually if needed"
}

# =============================================================================
# Phase 1: Collect state and all user decisions
# =============================================================================

clear
show_logo
echo ""

# --- Precompute state (no prompts) ---

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

openssh_installed=0; pacman -Q openssh &>/dev/null && openssh_installed=1
has_key=0;  [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]] && has_key=1
has_auth=0; [[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]] && has_auth=1
docker_installed=0;  pacman -Q docker  &>/dev/null && docker_installed=1
podman_installed=0;  pacman -Q podman  &>/dev/null && podman_installed=1
omp_installed=0;     command -v oh-my-posh &>/dev/null && omp_installed=1
snapper_installed=0; command -v snapper   &>/dev/null && snapper_installed=1
has_snapshots_mount=0; [[ -d /.snapshots ]] && has_snapshots_mount=1
snapper_configured=0
snapper list-configs 2>/dev/null | grep -q "root" && snapper_configured=1

UPDATE_MODE=0
[[ -f "$SETUP_STATE_FILE" ]] && UPDATE_MODE=1
load_first_run_date

SELECTED_PKGS=()
CONFIG_TAGS=()
PKG_PHASE_SKIP=0
CONFIG_PHASE_SKIP=0
INST_OMP="no"

if [[ $UPDATE_MODE -eq 0 ]]; then
  log_info "First run: recommended CLI packages (${installed_count}/${total} already installed)"
  echo -e "  ${DIM}These tools are optional extras (micro, fzf, tmux, fastfetch, git, ...).${NC}"
  echo ""
  echo "  1) Install all recommended packages"
  echo "  2) Choose which packages to install (by number)"
  echo "  3) Skip (do not install any of these packages now)"
  PKG_FIRST=$(read_choice "Choice (1-3): " "1" "2" "3")
  echo ""
  case "$PKG_FIRST" in
    1)
      SELECTED_PKGS=("${RECOMMENDED_PACKAGES[@]}")
      log_ok "All ${#SELECTED_PKGS[@]} recommended packages will be installed."
      ;;
    2)
      echo "Recommended packages (install by number, space-separated):"
      for _pkg_idx in "${!RECOMMENDED_PACKAGES[@]}"; do
        printf "  %2d) %s\n" "$((_pkg_idx + 1))" "${RECOMMENDED_PACKAGES[_pkg_idx]}"
      done
      log_ask "Enter numbers (e.g. 1 3 7) or \"all\": " >&2
      read -r pkg_line </dev/tty
      pkg_line=$(echo "$pkg_line" | tr '[:upper:]' '[:lower:]')
      if [[ "$pkg_line" == "all" ]]; then
        SELECTED_PKGS=("${RECOMMENDED_PACKAGES[@]}")
      else
        parse_pkg_indices "$pkg_line"
      fi
      [[ ${#SELECTED_PKGS[@]} -eq 0 ]] && { log_warn "No packages selected."; PKG_PHASE_SKIP=1; }
      ;;
    3)
      PKG_PHASE_SKIP=1
      log_info "Skipped: no recommended packages will be installed in this run."
      ;;
  esac
  echo ""

  if [[ $PKG_PHASE_SKIP -eq 1 ]]; then
    CONFIG_PHASE_SKIP=1
    log_info "Config files: skipped (no packages selected; run setup again to add packages and configs)."
  else
    log_info "Minidite config files from the repository (shell, editors, themes)"
    echo "  1) Install configs for everything you selected above (bash, matching tools, etc.)"
    echo "  2) Choose exactly which config bundles to install"
    echo "  3) Skip config download (packages only)"
    CFG_FIRST=$(read_choice "Choice (1-3): " "1" "2" "3")
    echo ""
    case "$CFG_FIRST" in
      1)
        _cfg_acc=(bashrc version)
        for _cfg_p in "${SELECTED_PKGS[@]}"; do
          while IFS= read -r _cfg_t; do [[ -n "$_cfg_t" ]] && _cfg_acc+=("$_cfg_t"); done < <(pkg_to_config_tags "$_cfg_p")
        done
        dedupe_tags "${_cfg_acc[@]}"
        log_ok "Will install config bundles: ${CONFIG_TAGS[*]}"
        ;;
      2)
        echo "Available config bundles:"
        echo "  1) bashrc + minidite shell integration (recommended)"
        echo "  2) minidite-version (shown in shell / fastfetch)"
        echo "  3) Oh My Posh theme (needs Oh My Posh binary; installed in a later step)"
        echo "  4) Micro editor (settings + colors)"
        echo "  5) Fastfetch"
        echo "  6) Tmux"
        log_ask "Enter numbers (e.g. 1 4 6): " >&2
        read -r cfg_line </dev/tty
        _cfg_pick=()
        for _cfg_n in $cfg_line; do
          case "$_cfg_n" in
            1) _cfg_pick+=(bashrc) ;;
            2) _cfg_pick+=(version) ;;
            3) _cfg_pick+=(omp) ;;
            4) _cfg_pick+=(micro) ;;
            5) _cfg_pick+=(fastfetch) ;;
            6) _cfg_pick+=(tmux) ;;
          esac
        done
        dedupe_tags "${_cfg_pick[@]}"
        [[ ${#CONFIG_TAGS[@]} -eq 0 ]] && { log_warn "No config bundles selected."; CONFIG_PHASE_SKIP=1; }
        ;;
      3)
        CONFIG_PHASE_SKIP=1
        log_info "Skipped: repository config files will not be downloaded."
        ;;
    esac
  fi
  echo ""

  if [[ ${#CONFIG_TAGS[@]} -gt 0 ]] && printf '%s\n' "${CONFIG_TAGS[@]}" | grep -qx omp; then
    INST_OMP="yes"
  fi
else
  log_info "Update mode: state file found (${SETUP_STATE_FILE})"
  [[ -n "${FIRST_RUN_DATE:-}" ]] && echo -e "  ${DIM}First setup: ${FIRST_RUN_DATE}${NC}"
  echo ""

  installed_recommended_list=()
  read -r -a installed_recommended_list <<< "$(list_installed_recommended)"
  ir_count=${#installed_recommended_list[@]}

  log_info "Recommended packages (minidite): ${ir_count} installed from this list"
  echo "  1) Update all installed recommended packages"
  echo "  2) Choose which installed packages to update"
  echo "  3) Skip (do not run pacman for this list)"
  PKG_UPD=$(read_choice "Choice (1-3): " "1" "2" "3")
  echo ""
  SELECTED_PKGS=()
  case "$PKG_UPD" in
    1)
      SELECTED_PKGS=("${installed_recommended_list[@]}")
      [[ ${#SELECTED_PKGS[@]} -eq 0 ]] && { log_warn "None of the recommended packages are installed."; PKG_PHASE_SKIP=1; }
      ;;
    2)
      if [[ $ir_count -eq 0 ]]; then
        log_warn "No recommended packages installed. Skipping package update."
        PKG_PHASE_SKIP=1
      else
        for _ir_idx in "${!installed_recommended_list[@]}"; do
          printf "  %2d) %s\n" "$((_ir_idx + 1))" "${installed_recommended_list[_ir_idx]}"
        done
        log_ask "Enter numbers to update (e.g. 1 2) or \"all\": " >&2
        read -r pkg_line2 </dev/tty
        pkg_line2=$(echo "$pkg_line2" | tr '[:upper:]' '[:lower:]')
        if [[ "$pkg_line2" == "all" ]]; then
          SELECTED_PKGS=("${installed_recommended_list[@]}")
        else
          SELECTED_PKGS=()
          for _ir_j in $pkg_line2; do
            [[ "$_ir_j" =~ ^[0-9]+$ ]] || continue
            ((_ir_j >= 1 && _ir_j <= ir_count)) || continue
            _ir_name="${installed_recommended_list[$((_ir_j - 1))]}"
            SELECTED_PKGS+=("$_ir_name")
          done
        fi
        [[ ${#SELECTED_PKGS[@]} -eq 0 ]] && { log_warn "No packages selected."; PKG_PHASE_SKIP=1; }
      fi
      ;;
    3)
      PKG_PHASE_SKIP=1
      log_info "Skipped: recommended packages will not be updated this run."
      ;;
  esac
  echo ""

  log_info "Refresh Minidite config files from the repository"
  echo "  1) Refresh configs for all installed tools that have a Minidite bundle (bash, micro, ...)"
  echo "  2) Choose which config bundles to refresh"
  echo "  3) Skip (leave config files unchanged)"
  CFG_UPD=$(read_choice "Choice (1-3): " "1" "2" "3")
  echo ""
  case "$CFG_UPD" in
    1)
      _upd_cfg_acc=(bashrc version)
      read -r -a _inst <<< "$(list_installed_recommended)"
      for _upd_p in "${_inst[@]}"; do
        while IFS= read -r _upd_t; do [[ -n "$_upd_t" ]] && _upd_cfg_acc+=("$_upd_t"); done < <(pkg_to_config_tags "$_upd_p")
      done
      dedupe_tags "${_upd_cfg_acc[@]}"
      ;;
    2)
      echo "Config bundles:"
      echo "  1) bashrc + shell integration"
      echo "  2) minidite-version"
      echo "  3) Oh My Posh theme"
      echo "  4) Micro"
      echo "  5) Fastfetch"
      echo "  6) Tmux"
      log_ask "Enter numbers (e.g. 1 3): " >&2
      read -r cfg_line3 </dev/tty
      _upd_pick=()
      for _upd_n in $cfg_line3; do
        case "$_upd_n" in
          1) _upd_pick+=(bashrc) ;;
          2) _upd_pick+=(version) ;;
          3) _upd_pick+=(omp) ;;
          4) _upd_pick+=(micro) ;;
          5) _upd_pick+=(fastfetch) ;;
          6) _upd_pick+=(tmux) ;;
        esac
      done
      dedupe_tags "${_upd_pick[@]}"
      [[ ${#CONFIG_TAGS[@]} -eq 0 ]] && { log_warn "No bundles selected."; CONFIG_PHASE_SKIP=1; }
      ;;
    3)
      CONFIG_PHASE_SKIP=1
      log_info "Skipped: config files will not be refreshed."
      ;;
  esac
  echo ""

  if [[ ${#CONFIG_TAGS[@]} -gt 0 ]] && printf '%s\n' "${CONFIG_TAGS[@]}" | grep -qx omp; then
    INST_OMP="yes"
  fi
fi

# ---- Decisions: Oh My Posh (binary) — optional if not already set by omp config tag ---
if [[ "$INST_OMP" != "yes" ]]; then
  log_info "Oh My Posh (prompt theme binary)"
  if [[ $omp_installed -eq 1 ]]; then
    echo "  1) Update / reinstall   2) Skip"
  else
    echo "  1) Install   2) Skip"
  fi
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_OMP="yes" || INST_OMP="no"
else
  log_info "Oh My Posh: will install or update (required for the theme you selected)"
fi
echo ""

# ---- Decisions: OpenSSH ----
log_info "OpenSSH server"
if [[ $openssh_installed -eq 1 ]]; then
  echo "  1) Update and ensure configured   2) Skip"
else
  echo "  1) Install   2) Skip"
fi
CHOICE_OPENSSH=$(read_choice "Choice (1-2): " "1" "2")
echo ""

# ---- Decisions: SSH server key pair ----
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
  echo "  1) Update   2) Skip"
else
  echo "  1) Install   2) Skip"
fi
CHOICE_DOCKER=$(read_choice "Choice (1-2): " "1" "2")
echo ""

# ---- Decisions: Podman ----
log_info "Podman"
if [[ $podman_installed -eq 1 ]]; then
  echo "  1) Update   2) Skip"
else
  echo "  1) Install   2) Skip"
fi
CHOICE_PODMAN=$(read_choice "Choice (1-2): " "1" "2")
echo ""

# ---- Decisions: Lazydocker ----
will_have_container=0
[[ $docker_installed -eq 1 || "$CHOICE_DOCKER" == "1" ]] && will_have_container=1
[[ $podman_installed -eq 1 || "$CHOICE_PODMAN" == "1" ]] && will_have_container=1
lazydocker_installed=0
command -v lazydocker &>/dev/null && lazydocker_installed=1
[[ -x "$HOME/.local/bin/lazydocker" ]] && lazydocker_installed=1
log_info "Lazydocker (TUI for Docker/Podman)"
if [[ $will_have_container -eq 1 ]]; then
  if [[ $lazydocker_installed -eq 1 ]]; then
    echo "  1) Update   2) Skip"
  else
    echo "  1) Install   2) Skip"
  fi
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_LAZYDOCKER="yes" || INST_LAZYDOCKER="no"
else
  INST_LAZYDOCKER="no"
  log_info "Skipped (no Docker/Podman)"
fi
echo ""

# ---- Decisions: Snapper ----
log_info "Snapper (Btrfs snapshots)"
if [[ $snapper_installed -eq 1 && $has_snapshots_mount -eq 1 ]]; then
  if [[ $snapper_configured -eq 1 ]]; then
    CONF_SNAPPER="no"
    log_ok "Already configured"
  else
    CONF_SNAPPER=$(read_yes_no "Configure Snapper for root snapshots? (yes/no): ")
  fi
else
  # snapper not installed or /.snapshots missing: offer to install+configure anyway
  echo "  1) Install and configure   2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  if [[ "$c" == "1" ]]; then
    CONF_SNAPPER="yes"
    snapper_installed=1       # will be installed in Step 10
    has_snapshots_mount=1     # will be created in Step 10
  else
    CONF_SNAPPER="no"
    [[ $snapper_installed -eq 0 ]] && log_info "Skipped (snapper not installed)"
    [[ $has_snapshots_mount -eq 0 ]] && log_info "Skipped (no /.snapshots)"
  fi
fi
echo ""

# ---- Decisions: Limine snapshot menu ----
log_info "Limine snapshot menu (boot menu with snapshots)"
# Offer regardless of current snapper state: Step 10 will install snapper if CONF_SNAPPER=yes
if [[ "$CONF_SNAPPER" == "yes" || ($snapper_installed -eq 1 && $has_snapshots_mount -eq 1) ]]; then
  echo "  1) Install/configure   2) Skip"
  c=$(read_choice "Choice (1-2): " "1" "2")
  [[ "$c" == "1" ]] && INST_LIMINE_MENU="yes" || INST_LIMINE_MENU="no"
else
  INST_LIMINE_MENU="no"
  log_info "Skipped (requires Snapper + /.snapshots)"
fi
echo ""

# ---- Confirm ----
proceed=$(read_yes_no "Apply all choices and run setup? (yes/no): ")
[[ "$proceed" != "yes" ]] && { log_info "Aborted."; exit 0; }
echo ""

# =============================================================================
# Phase 2: Execute all operations (no further prompts)
# =============================================================================

log_info "Phase 2: Executing..."
echo ""

s_done() { SUMMARY_DONE+=("$1"); }
s_skip() { SUMMARY_SKIP+=("$1"); }
s_warn() { SUMMARY_WARN+=("$1"); }

# ---- Step 1/13: Directories ----
log_info "Step 1/13: Directories"
for d in "${REQUIRED_DIRS[@]}"; do
  mkdir -p "$d" 2>/dev/null || { log_err "Cannot create $d"; exit 1; }
done
log_ok "Directories ready"
echo ""

# ---- Step 2/13: Recommended CLI packages ----
log_info "Step 2/13: Recommended CLI packages"
if [[ $PKG_PHASE_SKIP -eq 0 && ${#SELECTED_PKGS[@]} -gt 0 ]]; then
  if sudo pacman -S --noconfirm --needed "${SELECTED_PKGS[@]}" 2>/dev/null; then
    log_ok "Pacman finished for selected packages"
    s_done "Packages: ${SELECTED_PKGS[*]}"
  else
    log_warn "Pacman reported an error (some packages may be unavailable)"
    s_warn "Packages: pacman step had issues"
  fi
else
  log_info "Skipped"; s_skip "Recommended packages (pacman)"
fi
echo ""

# ---- Step 3/13: Config files ----
log_info "Step 3/13: Config files"
if [[ $CONFIG_PHASE_SKIP -eq 0 && ${#CONFIG_TAGS[@]} -gt 0 ]]; then
  if download_configs_by_tags "${CONFIG_TAGS[@]}"; then
    s_done "Config files: ${CONFIG_TAGS[*]}"
  else
    [[ $config_already -eq 1 ]] && s_warn "Config download incomplete (required files missing?)" || exit 1
  fi
else
  log_info "Skipped"; s_skip "Config files"
fi
echo ""

# ---- Step 4/13: Oh My Posh ----
log_info "Step 4/13: Oh My Posh"
if [[ "$INST_OMP" == "yes" ]]; then
  mkdir -p "$CONFIG/oh-my-posh"
  if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Oh My Posh binary installed/updated"
    s_done "Oh My Posh binary"
    if [[ ! -f "$CONFIG/oh-my-posh/theme.omp.json" ]]; then
      curl -fsSL "${REPO_URL}/home/.config/oh-my-posh/theme.omp.json" \
        -o "$CONFIG/oh-my-posh/theme.omp.json" 2>/dev/null || log_warn "Theme download failed (install config bundle \"Oh My Posh\" in a later run)"
    fi
  else
    log_warn "Install failed"; s_warn "Oh My Posh install failed"
  fi
  rm -rf "$HOME/.cache/oh-my-posh"
else
  log_info "Skipped"; s_skip "Oh My Posh"
fi
echo ""

# ---- Step 5/13: OpenSSH ----
log_info "Step 5/13: OpenSSH server"
_ssh_configured=0
if [[ "$CHOICE_OPENSSH" == "1" ]]; then
  sudo pacman -S --noconfirm --needed openssh 2>/dev/null \
    || { log_warn "Install failed"; s_warn "OpenSSH install failed"; }
  if pacman -Q openssh &>/dev/null; then
    configure_sshd_minidite
    sudo systemctl enable --now sshd.service 2>/dev/null \
      && log_ok "sshd enabled and hardened" \
      || log_warn "sshd enable failed"
    _ssh_configured=1
    s_done "OpenSSH: installed, hardened (PermitRootLogin=no, MaxAuthTries=3)"
  fi
else
  log_info "Skipped"; s_skip "OpenSSH"
fi
echo ""

# ---- Step 6/13: SSH keys ----
log_info "Step 6/13: SSH keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# 6a: Server key pair
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

# 6b: Client key for remote access
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

# 6c: Disable password authentication
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

# ---- Step 7/13: Docker ----
log_info "Step 7/13: Docker"
if [[ "$CHOICE_DOCKER" == "1" ]]; then
  if sudo pacman -S --noconfirm --needed docker docker-compose 2>/dev/null; then
    sudo systemctl enable --now docker.service 2>/dev/null
    sudo usermod -aG docker "$(whoami)" 2>/dev/null
    log_ok "Docker installed/updated"
    s_done "Docker: installed, $(whoami) in docker group"
    docker_installed=1
  else
    log_warn "Install failed"; s_warn "Docker install failed"
  fi
else
  log_info "Skipped"; s_skip "Docker"
fi
echo ""

# ---- Step 8/13: Podman ----
log_info "Step 8/13: Podman"
if [[ "$CHOICE_PODMAN" == "1" ]]; then
  if sudo pacman -S --noconfirm --needed podman podman-compose 2>/dev/null; then
    log_ok "Podman installed/updated"
    s_done "Podman: installed"
    podman_post_install
    podman_installed=1
  else
    log_warn "Install failed"; s_warn "Podman install failed"
  fi
else
  log_info "Skipped"; s_skip "Podman"
fi
echo ""

# ---- Step 9/13: Lazydocker ----
log_info "Step 9/13: Lazydocker"
if [[ "$INST_LAZYDOCKER" == "yes" ]]; then
  if curl -sSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
      | bash -s -- -d "$HOME/.local/bin" 2>/dev/null; then
    log_ok "Installed/updated to ~/.local/bin"
    s_done "Lazydocker: installed"
  else
    log_warn "Install failed"; s_warn "Lazydocker install failed"
  fi
else
  log_info "Skipped"; s_skip "Lazydocker"
fi
echo ""

# ---- Step 10/13: Snapper configuration ----
log_info "Step 10/13: Snapper configuration"
if [[ "$CONF_SNAPPER" == "yes" ]]; then
  # Install snapper if not present
  if ! command -v snapper &>/dev/null; then
    sudo pacman -S --noconfirm --needed snapper 2>/dev/null \
      || { log_warn "snapper install failed"; s_warn "Snapper: install failed"; CONF_SNAPPER="no"; }
  fi

  if [[ "$CONF_SNAPPER" == "yes" ]]; then
    sudo umount /.snapshots 2>/dev/null || true
    sudo rmdir  /.snapshots 2>/dev/null || true

    if sudo snapper -c root create-config /; then
      sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
      sudo mkdir -p /.snapshots
      sudo mount /.snapshots
      sudo chmod 750 /.snapshots
      echo "$SNAPPER_CONFIG" | sudo tee /etc/snapper/configs/root >/dev/null
      sudo btrfs quota enable / 2>/dev/null || true
      sudo systemctl enable --now snapper-timeline.timer 2>/dev/null || true
      sudo systemctl enable --now snapper-cleanup.timer  2>/dev/null || true
      for f in /etc/cron.hourly/snapper /etc/cron.daily/snapper; do
        [[ -f "$f" ]] && sudo mv "$f" "${f}.disabled" 2>/dev/null || true
      done
      (sudo crontab -l 2>/dev/null | grep -v 'snapper') 2>/dev/null | sudo crontab - 2>/dev/null || true
      log_ok "Snapper configured (timeline: 5 daily, number: 3 manual)"
      s_done "Snapper: timeline + number cleanup OK"
    else
      sudo mkdir -p /.snapshots
      sudo mount /.snapshots 2>/dev/null || true
      log_warn "Snapper create-config failed"
      s_warn  "Snapper: create-config failed"
    fi
  fi
else
  log_info "Skipped"; s_skip "Snapper"
fi
echo ""

# ---- Step 11/13: Limine snapshot menu (limine-snapper-sync) ----
log_info "Step 11/13: Limine snapshot menu (limine-snapper-sync)"

if [[ "$INST_LIMINE_MENU" == "yes" ]]; then

  # ------------------------------------------------------------------
  # 11a: Install limine-snapper-sync if not present
  # ------------------------------------------------------------------
  if ! command -v limine-update &>/dev/null; then
    LIMINE_INSTALLED=0

    # Try OPR (Omarchy Package Repository)
    if ! grep -q '^\[omarchy\]' /etc/pacman.conf 2>/dev/null; then
      log_info "Adding Omarchy Package Repository (OPR)..."
      printf '\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/stable/$arch\n' \
        | sudo tee -a /etc/pacman.conf >/dev/null
      sudo pacman -Sy 2>/dev/null || true
    fi

    if sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook 2>/dev/null; then
      LIMINE_INSTALLED=1
      log_ok "Installed from OPR (Omarchy Package Repository)"
    fi

    # Fallback: AUR via yay
    if [[ $LIMINE_INSTALLED -eq 0 ]] && ! command -v limine-update &>/dev/null; then
      log_info "OPR not available, falling back to AUR (yay)..."

      if ! command -v yay &>/dev/null; then
        sudo pacman -S --noconfirm --needed base-devel git 2>/dev/null || true
        YAY_DIR="/tmp/yay-build-$$"

        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$YAY_DIR" 2>/dev/null \
          || git clone --depth 1 https://aur.archlinux.org/yay.git "$YAY_DIR" 2>/dev/null \
          || { log_err "yay clone failed"; s_warn "Limine: yay clone failed"; INST_LIMINE_MENU="no"; }

        if [[ "$INST_LIMINE_MENU" == "yes" ]]; then
          (cd "$YAY_DIR" && makepkg -si --noconfirm) \
            || { log_err "yay build failed"; rm -rf "$YAY_DIR"; s_warn "Limine: yay build failed"; INST_LIMINE_MENU="no"; }
          rm -rf "$YAY_DIR"
        fi
      fi

      if [[ "$INST_LIMINE_MENU" == "yes" ]] && command -v yay &>/dev/null; then
        yay -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook mkinitcpio-btrfs 2>/dev/null \
          || { log_err "limine-snapper-sync AUR install failed"; s_warn "Limine: AUR packages failed"; INST_LIMINE_MENU="no"; }
      fi
    fi

    # Install mkinitcpio-btrfs separately if still missing
    if ! pacman -Q mkinitcpio-btrfs &>/dev/null; then
      grep -q '^\[omarchy\]' /etc/pacman.conf 2>/dev/null \
        && sudo pacman -S --noconfirm --needed mkinitcpio-btrfs 2>/dev/null || true
      pacman -Q mkinitcpio-btrfs &>/dev/null \
        || { command -v yay &>/dev/null && yay -S --noconfirm --needed mkinitcpio-btrfs 2>/dev/null || true; }
    fi
  fi

  # ------------------------------------------------------------------
  # 11b: Apply complete Limine configuration
  # ------------------------------------------------------------------
  if [[ "$INST_LIMINE_MENU" == "yes" ]] && command -v limine-update &>/dev/null; then

    # Write /etc/default/limine (replace @@CMDLINE@@ with real root UUID)
    CMDLINE="root=UUID=$(findmnt -n -o UUID / 2>/dev/null) rootfstype=btrfs rootflags=subvol=@ rw"
    sed "s|@@CMDLINE@@|${CMDLINE}|g" <<< "$LIMINE_DEFAULT_CONF" \
      | sudo tee /etc/default/limine >/dev/null
    log_ok "/etc/default/limine written"

    # Write /boot/limine.conf (base theme, no manual entries)
    # limine-snapper-sync will add /+Minidite, //linux, //Snapshots
    echo "$LIMINE_LIMINE_CONF" | sudo tee /boot/limine.conf >/dev/null
    log_ok "/boot/limine.conf written (Minidite theme, dynamic entries via limine-snapper-sync)"

    # Remove EFI "Minidite" entry created by install.sh (avoid NVRAM duplicates)
    EFI_NUM=$(efibootmgr 2>/dev/null | grep -i "Minidite" | sed 's/Boot\([0-9A-F]\{4\}\).*/\1/' | head -1)
    if [[ -n "$EFI_NUM" ]]; then
      sudo efibootmgr --delete-bootnum --bootnum "$EFI_NUM" 2>/dev/null || true
      log_ok "Removed previous EFI Minidite entry (${EFI_NUM})"
    fi

    # Add btrfs-overlayfs hook to mkinitcpio if mkinitcpio-btrfs is installed
    if pacman -Q mkinitcpio-btrfs &>/dev/null; then
      grep -q 'btrfs-overlayfs' /etc/mkinitcpio.conf \
        || sudo sed -i 's/ filesystems fsck/ filesystems btrfs-overlayfs fsck/' /etc/mkinitcpio.conf
      sudo mkinitcpio -P && log_ok "mkinitcpio regenerated with btrfs-overlayfs"
    fi

    # Remove "Arch Linux" entry possibly created by limine-entry-tool
    command -v limine-entry-tool &>/dev/null \
      && sudo limine-entry-tool --remove-os "Arch Linux" 2>/dev/null || true

    # Apply Limine: create new EFI entry and copy BOOTX64.EFI
    sudo limine-update && log_ok "limine-update completed"

    # Enable and start limine-snapper-sync
    sudo systemctl enable limine-snapper-sync.service 2>/dev/null \
      && log_ok "limine-snapper-sync.service enabled" || true
    sudo systemctl start limine-snapper-sync.service 2>/dev/null \
      && log_ok "limine-snapper-sync executed" || true

    # Hook limine-snapper-sync to snapper-cleanup so menu updates after each cleanup
    sudo mkdir -p /etc/systemd/system/snapper-cleanup.service.d
    printf '%s\n' '[Service]' 'ExecStartPost=/usr/bin/limine-snapper-sync' \
      | sudo tee /etc/systemd/system/snapper-cleanup.service.d/limine-sync.conf >/dev/null
    sudo systemctl daemon-reload
    log_ok "limine-snapper-sync hooked to snapper-cleanup.service"

    s_done "Limine snapshot menu: limine-snapper-sync"

  else
    if [[ "$INST_LIMINE_MENU" == "yes" ]]; then
      log_info "Skipped: limine-update not available after installation attempt"
    fi
    s_skip "Limine snapshot menu"
  fi

else
  log_info "Skipped"
  s_skip "Limine snapshot menu"
fi
echo ""

# ---- Step 12/13: fzf key bindings ----
log_info "Step 12/13: fzf"
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/key-bindings.bash ]] && cp /usr/share/fzf/key-bindings.bash "$CONFIG/fzf/" 2>/dev/null || true
  [[ -f /usr/share/fzf/completion.bash    ]] && cp /usr/share/fzf/completion.bash    "$CONFIG/fzf/" 2>/dev/null || true
  log_ok "Bindings copied"
  s_done "fzf: key bindings configured"
else
  log_info "fzf not installed, skipped"; s_skip "fzf"
fi
echo ""

# ---- Step 13/13: Cleanup and optimizations ----
log_info "Step 13/13: Cleanup and optimizations"
sudo pacman -Scc --noconfirm 2>/dev/null && log_ok "Pacman cache cleared" || true
orphans=$(pacman -Qdtq 2>/dev/null || true)
[[ -n "$orphans" ]] && sudo pacman -Rns --noconfirm $orphans 2>/dev/null && log_ok "Orphans removed" || true
sudo systemctl enable fstrim.timer 2>/dev/null && log_ok "fstrim.timer enabled" || true
pacman -Q pacman-contrib &>/dev/null && sudo systemctl enable paccache.timer 2>/dev/null && log_ok "paccache.timer enabled" || true
s_done "Cleanup: cache cleared, timers enabled"
echo ""

save_setup_state
log_ok "Setup state saved (${SETUP_STATE_FILE})"

if [[ -t 0 ]] && [[ -t 1 ]]; then
  echo ""
  read -r -n1 -s -p "Press any key to reload your shell with bash (or Ctrl+C to keep this session)... " </dev/tty || true
  echo ""
  show_summary
  trap - EXIT
  exec bash -l
fi

# Summary shown by trap on EXIT