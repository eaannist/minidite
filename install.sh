#!/bin/bash
# =============================================================================
# minidite - Arch Linux base install (interactive)
# =============================================================================
# Run as root from Arch Linux live ISO.
# Usage: curl -fsSL <url>/install | bash
# Reads from /dev/tty for interactive prompts.
# =============================================================================
set -euo pipefail

INSTALL_LOG="${INSTALL_LOG:-install.log}"
[[ "$INSTALL_LOG" != /* ]] && INSTALL_LOG="$(pwd)/$INSTALL_LOG"
exec > >(tee "$INSTALL_LOG") 2>&1
echo "=== Minidite install started $(date -Iseconds) ==="

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
  echo -e "  ${GREEN}#Install${NC}"
}

# -----------------------------------------------------------------------------
# Logging and input helpers (prompts/errors to stderr for use in command substitution)
# -----------------------------------------------------------------------------
log_info()  { echo -e "${LCYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${LGREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${LYELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${LRED}[x]${NC} $1"; }
log_ask()   { echo -e "${LBLUE}[?]${NC} $1"; }
die()       { log_err "$1"; exit 1; }

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
# Validation and helpers
# -----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || { log_err "Run as root"; exit 1; }

list_disks_raw()  { lsblk -d -n -o NAME,SIZE,TYPE | awk '$3=="disk" {print $1, $2}'; }
valid_user()      { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#1} -ge 3 && ${#1} -le 32 ]]; }
valid_host()      { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] && [[ ${#1} -le 63 ]]; }
keymap_for()      { case "$1" in *it_IT*) echo it;; *en_US*) echo us;; *de_DE*) echo de;; *fr_FR*) echo fr;; *es_ES*) echo es;; *) echo us;; esac; }
list_locales()    { grep -E '^#?[a-z]{2}_[A-Z]{2}\.UTF-8' /etc/locale.gen 2>/dev/null | sed 's/^#//' | awk '{print $1}' | head -20; }
list_tz()         { find /usr/share/zoneinfo -type f ! -name "*.tab" 2>/dev/null | sed 's|/usr/share/zoneinfo/||' | sort | head -30; }

mirror_country_from_locale() {
  case "$1" in
    it_IT*) echo "IT" ;; en_US*) echo "US" ;; en_GB*) echo "GB" ;;
    de_DE*) echo "DE" ;; fr_FR*) echo "FR" ;; es_ES*) echo "ES" ;;
    *) echo "" ;;
  esac
}

detect_firmware_packages() {
  lspci -nn 2>/dev/null | sed -n 's/.*\[\([0-9a-f]\{4\}\):[0-9a-f]\{4\}\].*/\1/p' | tr '[:upper:]' '[:lower:]' | sort -u | while read -r v; do
    case "$v" in
      8086) echo "linux-firmware-intel" ;;
      10ec) echo "linux-firmware-realtek" ;;
      168c) echo "linux-firmware-atheros" ;;
      1002) echo "linux-firmware-amdgpu"; echo "linux-firmware-radeon" ;;
      14e4) echo "linux-firmware-broadcom" ;;
      10de) echo "linux-firmware-nvidia" ;;
      1b4b) echo "linux-firmware-marvell" ;;
      17cb) echo "linux-firmware-qcom" ;;
      14c3) echo "linux-firmware-mediatek" ;;
      *) ;;
    esac
  done | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# =============================================================================
# Interactive prompts (gather all choices before destructive actions)
# =============================================================================
clear
show_logo
echo ""

# ---- Step 1: Disk (destructive; confirm explicitly) ----
log_info "Step 1/6: Select target disk (all data will be erased)"
echo ""
mapfile -t _disk_list < <(list_disks_raw)
[[ ${#_disk_list[@]} -eq 0 ]] && die "No disks found"
for i in "${!_disk_list[@]}"; do
  printf "  %d) /dev/%s (%s)\n" $((i+1)) "${_disk_list[i]%% *}" "${_disk_list[i]#* }"
done
echo ""
while true; do
  choice=$(read_choice "Disk (1-${#_disk_list[@]}): " $(seq 1 ${#_disk_list[@]}))
  DISK="/dev/${_disk_list[$((choice-1))]%% *}"
  log_warn "All data on ${DISK} will be erased."
  c=$(read_yes_no "Continue? (yes/no): ")
  [[ "$c" == "yes" ]] && break
done
echo ""

# ---- Step 2: System identity ----
log_info "Step 2/6: Hostname and user"
echo ""
log_ask "Hostname (default: minidite): "
read -r HOSTNAME </dev/tty
HOSTNAME=$(echo "${HOSTNAME:-minidite}" | tr -d ' \t')
until valid_host "$HOSTNAME"; do log_err "Invalid hostname"; log_ask "Hostname: "; read -r HOSTNAME </dev/tty; HOSTNAME=$(echo "$HOSTNAME" | tr -d ' \t'); done

log_ask "Username (default: admin): "
read -r USER </dev/tty
USER=$(echo "${USER:-admin}" | tr -d ' \t')
until valid_user "$USER"; do log_err "Invalid username (3-32 chars, a-z _ -)"; log_ask "Username: "; read -r USER </dev/tty; USER=$(echo "$USER" | tr -d ' \t'); done

while true; do
  log_ask "Password for ${USER}: "
  read -rs PASSWORD </dev/tty
  echo ""
  [[ -n "$PASSWORD" ]] || { log_err "Empty password"; continue; }
  log_ask "Confirm password: "
  read -rs PASSWORD_CONFIRM </dev/tty
  echo ""
  [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] && break
  log_err "Mismatch"
done
echo ""

# ---- Step 3: Localization ----
log_info "Step 3/6: Locale, keymap, timezone"
echo ""
log_info "Locale: 1) Italian (it_IT.UTF-8)  2) English (en_US.UTF-8)  3) Custom"
lc=$(read_choice "Choice (1-3): " "1" "2" "3")
case "$lc" in
  1) LOCALE="it_IT.UTF-8" ;;
  2) LOCALE="en_US.UTF-8" ;;
  3) log_info "Examples:"; list_locales; log_ask "Locale: "; read -r LOCALE </dev/tty ;;
esac

log_info "Keymap: 1) it  2) us  3) From locale  4) de  5) fr  6) es  7) Custom"
km=$(read_choice "Choice (1-7): " "1" "2" "3" "4" "5" "6" "7")
case "$km" in
  1) KEYMAP="it" ;; 2) KEYMAP="us" ;; 3) KEYMAP=$(keymap_for "$LOCALE") ;;
  4) KEYMAP="de" ;; 5) KEYMAP="fr" ;; 6) KEYMAP="es" ;;
  7) log_ask "Keymap: "; read -r KEYMAP </dev/tty; KEYMAP=$(echo "${KEYMAP:-us}" | tr -d ' '); [[ -z "$KEYMAP" ]] && KEYMAP="us" ;;
esac

log_info "Timezone: 1) Europe/Rome  2) Europe/London  3) America/New_York  4) Custom"
tz=$(read_choice "Choice (1-4): " "1" "2" "3" "4")
case "$tz" in
  1) TIMEZONE="Europe/Rome" ;; 2) TIMEZONE="Europe/London" ;; 3) TIMEZONE="America/New_York" ;;
  4) log_info "Examples:"; list_tz; log_ask "Timezone: "; read -r TIMEZONE </dev/tty ;;
esac
echo ""

# ---- Step 4: Mirror region (for pacman during install) ----
log_info "Step 4/6: Mirror region (for package download)"
_mc=$(mirror_country_from_locale "$LOCALE"); _mclabel="${_mc:-all}"
log_info "1) From locale (${_mclabel})  2) IT  3) DE  4) US  5) GB  6) All  7) Custom"
mr=$(read_choice "Choice (1-7): " "1" "2" "3" "4" "5" "6" "7")
case "$mr" in
  1) MIRROR_COUNTRY=$(mirror_country_from_locale "$LOCALE"); [[ -z "$MIRROR_COUNTRY" ]] && MIRROR_COUNTRY="all" ;;
  2) MIRROR_COUNTRY="IT" ;; 3) MIRROR_COUNTRY="DE" ;; 4) MIRROR_COUNTRY="US" ;; 5) MIRROR_COUNTRY="GB" ;;
  6) MIRROR_COUNTRY="all" ;;
  7) log_ask "Country code (e.g. IT, FR): "; read -r MIRROR_COUNTRY </dev/tty; MIRROR_COUNTRY=$(echo "${MIRROR_COUNTRY:-all}" | tr '[:upper:]' '[:lower:]' | cut -c1-2); [[ -z "$MIRROR_COUNTRY" ]] && MIRROR_COUNTRY="all" ;;
esac
echo ""

# ---- Step 5: Firmware ----
log_info "Step 5/6: Firmware"
log_info "1) Auto (detect from this machine)  2) Full (linux-firmware, ~700MB) 3) None (e.g. VM)"
fw=$(read_choice "Choice (1-3): " "1" "2" "3")
case "$fw" in
  1)
    FIRMWARE_PACKAGES=$(detect_firmware_packages)
    if [[ -z "$FIRMWARE_PACKAGES" ]]; then
      log_warn "No PCI devices matched; using full firmware"
      FIRMWARE_PACKAGES="linux-firmware"
    else
      log_info "Auto-detected: ${FIRMWARE_PACKAGES}"
    fi
    ;;
  2) FIRMWARE_PACKAGES="linux-firmware" ;;
  3) FIRMWARE_PACKAGES="" ;;
esac
echo ""

# ---- Step 6: Summary and confirmation ----
log_info "Step 6/6: Summary"
echo ""
echo -e "  ${BOLD}Disk:${NC}     ${DISK}"
echo -e "  ${BOLD}Hostname:${NC} ${HOSTNAME}"
echo -e "  ${BOLD}User:${NC}     ${USER}"
echo -e "  ${BOLD}Locale:${NC}   ${LOCALE}"
echo -e "  ${BOLD}Keymap:${NC}   ${KEYMAP}"
echo -e "  ${BOLD}Timezone:${NC} ${TIMEZONE}"
echo -e "  ${BOLD}Mirror:${NC}   ${MIRROR_COUNTRY}"
echo -e "  ${BOLD}Firmware:${NC} ${FIRMWARE_PACKAGES:-none}"
echo ""
confirm=$(read_yes_no "Proceed with install? (yes/no): ")
[[ "$confirm" == "yes" ]] || die "Aborted by user"

# -----------------------------------------------------------------------------
# Step runner: run a step and die on failure (optional validation)
# -----------------------------------------------------------------------------
run_step() {
  local name="$1"
  local cmd="$2"
  log_info "Step: ${name}..."
  if eval "$cmd"; then
    log_ok "${name} done"
    return 0
  fi
  die "${name} failed"
}

# =============================================================================
# Execution: incremental steps with validation
# =============================================================================

# --- Step 1: Network ---
run_step "Network check" 'ping -c 1 -W 3 8.8.8.8 &>/dev/null || ping -c 1 -W 3 archlinux.org &>/dev/null'
echo ""

# --- Step 2: Host prep ---
run_step "Host prep (mirrorlist, keymap)" '
  ( [[ -z "$MIRROR_COUNTRY" || "$MIRROR_COUNTRY" == "all" ]] ) || \
    { curl -sL "https://archlinux.org/mirrorlist/?country=${MIRROR_COUNTRY}&protocol=https&use_mirror_status=on" | sed "s/^#Server/Server/" > /etc/pacman.d/mirrorlist || true; }
  pacman -Sy --noconfirm 2>/dev/null || true
  printf "KEYMAP=%s\nFONT=lat1-16\n" "${KEYMAP}" > /etc/vconsole.conf
  loadkeys "${KEYMAP}" 2>/dev/null || true
  true
'
echo ""

# --- Step 3: Partition and format ---
run_step "Partition (GPT, EFI 512MiB + Btrfs)" '
  parted -s "${DISK}" mklabel gpt && \
  parted -s "${DISK}" mkpart primary fat32 1MiB 512MiB && \
  parted -s "${DISK}" mkpart primary btrfs 512MiB 100% && \
  parted -s "${DISK}" set 1 esp on
'
if [[ "${DISK}" =~ nvme ]]; then BOOT_PART="${DISK}p1"; ROOT_PART="${DISK}p2"; else BOOT_PART="${DISK}1"; ROOT_PART="${DISK}2"; fi

run_step "Format (FAT32 + Btrfs)" 'mkfs.fat -F32 "${BOOT_PART}" && mkfs.btrfs -f -L root "${ROOT_PART}"'
echo ""

# --- Step 4: Btrfs subvolumes and mount ---
run_step "Btrfs subvolumes (@, @snapshots)" '
  mount "${ROOT_PART}" /mnt && \
  btrfs subvolume create /mnt/@ && \
  btrfs subvolume create /mnt/@snapshots && \
  umount /mnt
'
BTRFS_OPTS="compress=zstd:1,space_cache=v2,noatime,discard=async,ssd,commit=120"
run_step "Mount root and ESP" '
  mount -o "subvol=@,${BTRFS_OPTS}" "${ROOT_PART}" /mnt && \
  mkdir -p /mnt/.snapshots /mnt/boot && \
  mount -o "subvol=@snapshots,${BTRFS_OPTS}" "${ROOT_PART}" /mnt/.snapshots && \
  mount "${BOOT_PART}" /mnt/boot
'
ROOT_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
BOOT_UUID=$(blkid -s UUID -o value "${BOOT_PART}")
[[ -n "$ROOT_UUID" && -n "$BOOT_UUID" ]] || die "Could not get UUIDs for root or boot partition"
echo ""

# --- Step 5: Pacstrap ---
run_step "vconsole.conf (pre-pacstrap)" '
  mkdir -p /mnt/etc && printf "KEYMAP=%s\nFONT=lat1-16\n" "${KEYMAP}" > /mnt/etc/vconsole.conf && chmod 644 /mnt/etc/vconsole.conf
'
BASE_PKGS="base linux sudo networkmanager curl limine btrfs-progs efibootmgr"
[[ -n "$FIRMWARE_PACKAGES" ]] && BASE_PKGS="${BASE_PKGS} ${FIRMWARE_PACKAGES}"
run_step "Pacstrap base system" "pacstrap /mnt $BASE_PKGS"
[[ -n "$MIRROR_COUNTRY" && "$MIRROR_COUNTRY" != "all" ]] && cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
pacman -Scc --noconfirm 2>/dev/null || true
echo ""

# --- Step 6: fstab (deterministic; tabs between fields) ---
run_step "fstab" '
  {
    echo "# Root (Btrfs subvol=@)"
    echo -e "UUID=${ROOT_UUID}\t/\tbtrfs\tsubvol=@,${BTRFS_OPTS}\t0\t0"
    echo "# Snapshots"
    echo -e "UUID=${ROOT_UUID}\t/.snapshots\tbtrfs\tsubvol=@snapshots,${BTRFS_OPTS}\t0\t0"
    echo "# ESP at /boot"
    echo -e "UUID=${BOOT_UUID}\t/boot\tvfat\tumask=0077\t0\t2"
  } > /mnt/etc/fstab
  grep -q "subvol=@" /mnt/etc/fstab || die "fstab missing subvol=@"
'
ESP_PART_NUM=1
_LOCALE_ESC="${LOCALE//./\\.}"
echo ""

# --- Step 7: Passwords in temp files (no escaping issues in heredoc) ---
PASSFILE_ROOT="/mnt/tmp/.root_pass"
PASSFILE_USER="/mnt/tmp/.user_pass"
mkdir -p /mnt/tmp
echo -n "$PASSWORD" > "$PASSFILE_ROOT"
echo -n "$PASSWORD" > "$PASSFILE_USER"
chmod 600 "$PASSFILE_ROOT" "$PASSFILE_USER"
log_ok "Password files prepared (will be removed in chroot)"
echo ""

# --- Step 8: Chroot configuration ---
log_info "Step: Chroot configuration..."
( arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -e
fail() { echo "ERROR: \$1" >&2; exit 1; }

# --- 8a: Root password first (required for emergency mode; use chpasswd from file) ---
if [[ -f /tmp/.root_pass ]]; then
  RP=\$(cat /tmp/.root_pass)
  echo "root:\$RP" | chpasswd || fail "chpasswd root failed"
  passwd -u root 2>/dev/null || true
  rm -f /tmp/.root_pass
fi
grep -q "subvol=@" /etc/fstab || fail "fstab missing subvol=@"

# --- 8b: Base system config ---
[[ -f /etc/vconsole.conf ]] || { printf "KEYMAP=%s\nFONT=lat1-16\n" "${KEYMAP}" > /etc/vconsole.conf; }
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i "/^#${_LOCALE_ESC}/s/^#//" /etc/locale.gen
locale-gen || fail "locale-gen"
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   %s.localdomain %s\n' "${HOSTNAME}" "${HOSTNAME}" > /etc/hosts
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nSystemMaxUse=50M" > /etc/systemd/journald.conf.d/00-size.conf

# --- 8c: Limine (minimal boot entry; setup overwrites with full config) ---
mkdir -p /boot/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI || fail "Copy Limine EFI"

# limine.conf requires at least one entry; "config file contains non valid entries" if no entries
cat > /boot/limine.conf <<LIMINE
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

/Minidite
  protocol: linux
  path: boot():/vmlinuz-linux
  module_path: boot():/initramfs-linux.img
  cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw
LIMINE

efibootmgr --create --disk "${DISK}" --part "${ESP_PART_NUM}" \
  --label "Minidite" \
  --loader "\EFI\BOOT\BOOTX64.EFI" \
  --unicode || fail "efibootmgr failed"

# --- 8d: mkinitcpio ---
# Arch ships systemd-based HOOKS by default since mkinitcpio v40 (PKGBUILD -Dsystemd_hooks=true).
# Switch to udev-based HOOKS (busybox init) for reliability with Btrfs+Limine (same as Omarchy).
sed -i 's/^MODULES=(.*)/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf
grep -q "^MODULES=(btrfs)" /etc/mkinitcpio.conf || fail "mkinitcpio.conf: MODULES not set"
grep -q "^HOOKS=.*udev" /etc/mkinitcpio.conf || fail "mkinitcpio.conf: HOOKS not set to udev"
echo "--- mkinitcpio.conf (MODULES + HOOKS) ---"
grep -E "^(MODULES|HOOKS)=" /etc/mkinitcpio.conf
echo "---"
mkinitcpio -P
[[ -f /boot/initramfs-linux.img ]] || fail "mkinitcpio: no initramfs found"
[[ -f /boot/vmlinuz-linux ]] || fail "mkinitcpio: no kernel found at /boot/vmlinuz-linux"
[[ -f /etc/os-release ]] || fail "/etc/os-release missing"
[[ -L /sbin/init || -f /sbin/init ]] || fail "/sbin/init missing (systemd not installed?)"

# --- 8e: User and sudo ---
useradd -m -G wheel -s /bin/bash "${USER}" || fail "useradd failed"
if [[ -f /tmp/.user_pass ]]; then
  UP=\$(cat /tmp/.user_pass)
  echo "${USER}:\$UP" | chpasswd || fail "chpasswd user failed"
  rm -f /tmp/.user_pass
fi
echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER}
chmod 0440 /etc/sudoers.d/${USER}
mkdir -p /home/${USER}/.ssh
chmod 700 /home/${USER}/.ssh
chown -R ${USER}:${USER} /home/${USER}

CHROOT_EOF
) || die "Chroot configuration failed. Check the last ERROR line above."
log_ok "Chroot configuration done"
echo ""

# --- Step 9: Post-chroot (enable services, fix root shell) ---
run_step "Post-chroot (NetworkManager, root shell)" '
  systemctl --root=/mnt enable NetworkManager.service 2>/dev/null || true
  sed -i "s|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1/bin/bash|" /mnt/etc/passwd
'
# Set root and user passwords from HOST (chpasswd -R or chroot chpasswd from file)
run_step "Set root and user passwords (from host)" '
  if echo "root:${PASSWORD}" | chpasswd -R /mnt 2>/dev/null; then
    echo "${USER}:${PASSWORD}" | chpasswd -R /mnt 2>/dev/null || true
  else
    echo "root:${PASSWORD}" > /mnt/tmp/.chp && arch-chroot /mnt chpasswd < /mnt/tmp/.chp && rm -f /mnt/tmp/.chp
    echo "${USER}:${PASSWORD}" > /mnt/tmp/.chp && arch-chroot /mnt chpasswd < /mnt/tmp/.chp && rm -f /mnt/tmp/.chp
  fi
  arch-chroot /mnt passwd -u root 2>/dev/null || true
'
rm -f /mnt/tmp/.root_pass /mnt/tmp/.user_pass 2>/dev/null || true
echo ""

# --- Step 10: User dirs ---
run_step "User dirs" '
  mkdir -p /mnt/home/${USER}/.config /mnt/home/${USER}/.local/bin /mnt/home/${USER}/.cache
  uid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f3)
  gid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f4)
  [[ -n "$uid" && -n "$gid" ]] && chown -R "${uid}:${gid}" /mnt/home/${USER} || true
'

# --- Step 11: Pre-unmount verification (debug output) ---
log_info "Pre-unmount verification..."
echo "--- /mnt/etc/fstab ---"
cat /mnt/etc/fstab
echo "--- /mnt/boot/limine.conf (minimal; setup overwrites) ---"
cat /mnt/boot/limine.conf 2>/dev/null || echo "(not found)"
echo "--- /mnt/boot/EFI/BOOT/ ---"
ls -la /mnt/boot/EFI/BOOT/ 2>/dev/null || echo "(not found)"
echo "--- mkinitcpio.conf (MODULES + HOOKS) ---"
grep -E "^(MODULES|HOOKS)=" /mnt/etc/mkinitcpio.conf
echo "--- /sbin/init target ---"
ls -la /mnt/sbin/init 2>/dev/null || echo "/sbin/init NOT FOUND"
echo "--- /etc/os-release ---"
head -3 /mnt/etc/os-release 2>/dev/null || echo "(not found)"
echo "--- root entry in /etc/passwd ---"
grep "^root:" /mnt/etc/passwd
echo "--- root entry in /etc/shadow (lock status) ---"
cut -d: -f1,2 /mnt/etc/shadow | grep "^root:" | sed 's/:.*/:***/' 
root_hash=$(awk -F: '/^root:/ {print $2}' /mnt/etc/shadow)
if [[ "$root_hash" == "!" || "$root_hash" == "!!" || "$root_hash" == "*" ]]; then
  log_warn "root account appears LOCKED (hash='${root_hash}')"
else
  log_ok "root account appears UNLOCKED"
fi
echo "--- Boot files on ESP ---"
ls -la /mnt/boot/vmlinuz-linux /mnt/boot/initramfs-linux.img 2>/dev/null
echo "---"

run_step "Unmount" 'umount -R /mnt'
echo ""

log_ok "Install complete."
echo ""
echo -e "${BOLD}${LCYAN}=== Install Summary ===${NC}"
echo -e "  ${LCYAN}Disk:${NC}        ${LWHITE}${DISK}${NC} (GPT, ESP 512MiB + Btrfs)"
echo -e "  ${LCYAN}Btrfs:${NC}       ${LWHITE}subvolumes @, @snapshots${NC}"
echo -e "  ${LCYAN}ESP:${NC}         ${LWHITE}/boot${NC} (FAT32, ${GRAY}${BOOT_UUID}${NC})"
echo -e "  ${LCYAN}Root:${NC}        ${GRAY}UUID=${ROOT_UUID}${NC}"
echo -e "  ${LCYAN}Bootloader:${NC}  ${LWHITE}Limine${NC} (basic EFI)"
echo -e "  ${LCYAN}Initramfs:${NC}   ${LWHITE}mkinitcpio${NC} (udev hooks, btrfs module)"
echo -e "  ${LCYAN}Hostname:${NC}    ${LYELLOW}${HOSTNAME}${NC}"
echo -e "  ${LCYAN}User:${NC}        ${LYELLOW}${USER}${NC} (wheel, NOPASSWD sudo)"
echo -e "  ${LCYAN}Locale:${NC}      ${LWHITE}${LOCALE} / ${KEYMAP}${NC}"
echo -e "  ${LCYAN}Timezone:${NC}    ${LWHITE}${TIMEZONE}${NC}"
echo -e "  ${LCYAN}Services:${NC}    ${LWHITE}NetworkManager${NC}"
echo -e "  ${LCYAN}Firmware:${NC}    ${LWHITE}${FIRMWARE_PACKAGES:-none}${NC}"
echo -e "  ${LCYAN}Packages:${NC}    ${GRAY}${BASE_PKGS}${NC}"
echo -e "  ${LCYAN}Log:${NC}         ${GRAY}${INSTALL_LOG}${NC}"
echo ""
echo -e "  ${BOLD}${LWHITE}Next steps:${NC}"
echo -e "    ${GRAY}1.${NC} ${LYELLOW}reboot${NC}"
echo -e "    ${GRAY}2.${NC} Log in as ${BOLD}${LYELLOW}${USER}${NC}"
echo -e "    ${GRAY}3.${NC} Run:  ${LYELLOW}curl -fsSL https://x.acridite.cc/minidite/setup | bash${NC}"
echo ""
