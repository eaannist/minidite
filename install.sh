#!/bin/bash
# =============================================================================
# minidite - Arch Linux base install (interactive)
# =============================================================================
# Run as root from Arch Linux live ISO.
# Usage: curl -fsSL <url>/install | bash
# Reads from /dev/tty for interactive prompts.
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

readonly VERSION="${VERSION:-N/A}"

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
# Logging and input helpers (prompts/errors to stderr for use in command substitution)
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
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- minimal Arch install${NC}"
echo ""

# ---- Step 1: Disk (destructive; confirm explicitly) ----
log_info "Step 1/6: Select target disk (all data will be erased)"
echo ""
mapfile -t _disk_list < <(list_disks_raw)
[[ ${#_disk_list[@]} -eq 0 ]] && { log_err "No disks found"; exit 1; }
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
log_ask "Hostname (default: arch): "
read -r HOSTNAME </dev/tty
HOSTNAME=$(echo "${HOSTNAME:-arch}" | tr -d ' \t')
until valid_host "$HOSTNAME"; do log_err "Invalid hostname"; log_ask "Hostname: "; read -r HOSTNAME </dev/tty; HOSTNAME=$(echo "$HOSTNAME" | tr -d ' \t'); done

log_ask "Username (default: arch): "
read -r USER </dev/tty
USER=$(echo "${USER:-arch}" | tr -d ' \t')
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
log_info "1) Full (linux-firmware, ~700MB)  2) Auto (detect from this machine)  3) None (e.g. VM)"
fw=$(read_choice "Choice (1-3): " "1" "2" "3")
case "$fw" in
  1) FIRMWARE_PACKAGES="linux-firmware" ;;
  2)
    FIRMWARE_PACKAGES=$(detect_firmware_packages)
    if [[ -z "$FIRMWARE_PACKAGES" ]]; then
      log_warn "No PCI devices matched; using full firmware"
      FIRMWARE_PACKAGES="linux-firmware"
    else
      log_info "Auto-detected: ${FIRMWARE_PACKAGES}"
    fi
    ;;
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
[[ "$confirm" == "yes" ]] || { log_err "Aborted"; exit 1; }

# =============================================================================
# Execution (network, partition, install, configure)
# =============================================================================

log_info "Checking network..."
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null && ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
  log_err "No internet. Configure network first."
  exit 1
fi
log_ok "Network ok"
echo ""

if [[ -n "$MIRROR_COUNTRY" && "$MIRROR_COUNTRY" != "all" ]]; then
  log_info "Updating mirrorlist (${MIRROR_COUNTRY})..."
  curl -sL "https://archlinux.org/mirrorlist/?country=${MIRROR_COUNTRY}&protocol=https&use_mirror_status=on" | sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
fi
pacman -Sy --noconfirm || true
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
loadkeys "${KEYMAP}" 2>/dev/null || true

log_info "Partitioning ${DISK} (GPT, EFI 256MiB + root)..."
parted -s "${DISK}" mklabel gpt
parted -s "${DISK}" mkpart primary fat32 1MiB 256MiB
parted -s "${DISK}" mkpart primary btrfs 256MiB 100%
parted -s "${DISK}" set 1 esp on

if [[ "${DISK}" =~ nvme ]]; then
  BOOT_PART="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  BOOT_PART="${DISK}1"
  ROOT_PART="${DISK}2"
fi

log_info "Formatting (FAT32 + Btrfs)..."
mkfs.fat -F32 "${BOOT_PART}"
mkfs.btrfs -f -L root "${ROOT_PART}"

log_info "Creating Btrfs subvolumes (@, @home)..."
mount "${ROOT_PART}" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Mount options: zstd:3 (balance compression/speed), noatime (fewer writes), discard=async (SSD TRIM), ssd, commit=120 (stability)
BTRFS_OPTS="compress=zstd:3,noatime,discard=async,ssd,commit=120"
log_info "Mounting root (@) and @home..."
mount -o "subvol=@,${BTRFS_OPTS}" "${ROOT_PART}" /mnt
mkdir -p /mnt/home
mount -o "subvol=@home,${BTRFS_OPTS}" "${ROOT_PART}" /mnt/home
mkdir -p /mnt/boot
mount "${BOOT_PART}" /mnt/boot

BASE_PKGS="base linux sudo networkmanager curl grub efibootmgr btrfs-progs"
[[ -n "$FIRMWARE_PACKAGES" ]] && BASE_PKGS="${BASE_PKGS} ${FIRMWARE_PACKAGES}"
# Do not use -c: on live ISO the host root (/) has very little space; use target cache (/mnt/var/cache) so downloads go to the target disk. Cache is cleared in chroot below.
pacstrap /mnt $BASE_PKGS
[[ -n "$MIRROR_COUNTRY" && "$MIRROR_COUNTRY" != "all" ]] && cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
pacman -Scc --noconfirm 2>/dev/null || true

genfstab -U /mnt > /mnt/etc/fstab

_LOCALE_ESC="${LOCALE//./\\.}"
log_info "Configuring system (chroot)..."
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i "/^#${_LOCALE_ESC}/s/^#//" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   %s.localdomain %s\n' "${HOSTNAME}" "${HOSTNAME}" > /etc/hosts
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nSystemMaxUse=50M" > /etc/systemd/journald.conf.d/00-size.conf
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
# Explicit btrfs module and fsck helper (btrfs-progs): avoid mkinitcpio build errors and "No fsck helpers found"
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P
systemctl enable NetworkManager.service
useradd -m -G wheel -s /bin/bash "${USER}"
echo "${USER}:${PASSWORD}" | chpasswd
echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER}
chmod 0440 /etc/sudoers.d/${USER}
mkdir -p /home/${USER}/.ssh
chmod 700 /home/${USER}/.ssh
chown -R ${USER}:${USER} /home/${USER}
chsh -s /bin/bash root 2>/dev/null || true
pacman -Scc --noconfirm 2>/dev/null || true
EOF

log_info "Creating user directories and setting ownership..."
mkdir -p /mnt/home/${USER}/.config /mnt/home/${USER}/.local/bin /mnt/home/${USER}/.cache
uid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f3)
gid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f4)
[[ -n "$uid" && -n "$gid" ]] && chown -R "${uid}:${gid}" /mnt/home/${USER}

log_info "Unmounting..."
umount -R /mnt

echo ""
log_ok "Install complete."
echo ""
echo "  Next:"
echo "    1. reboot"
echo "    2. Log in as ${USER}"
echo "    3. Run:  curl -fsSL https://x.acridite.cc/minidite/setup | bash"
echo ""
