#!/bin/bash
# minidite - Base OS install only (interactive)
# Run as root from Arch ISO. Safe to pipe: curl ... | bash (reads from /dev/tty).
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
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

[[ $EUID -eq 0 ]] || { log_err "Run as root"; exit 1; }

# List disks as "NAME SIZE"; used to build numbered menu
list_disks_raw() { lsblk -d -n -o NAME,SIZE,TYPE | awk '$3=="disk" {print $1, $2}'; }
valid_disk()  { [[ -b "$1" ]] && lsblk -d -n -o NAME "$1" &>/dev/null; }
valid_user()  { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#1} -ge 3 && ${#1} -le 32 ]]; }
valid_host()  { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] && [[ ${#1} -le 63 ]]; }
keymap_for()  { case "$1" in *it_IT*) echo it;; *en_US*) echo us;; *de_DE*) echo de;; *fr_FR*) echo fr;; *es_ES*) echo es;; *) echo us;; esac; }
list_locales(){ grep -E '^#?[a-z]{2}_[A-Z]{2}\.UTF-8' /etc/locale.gen 2>/dev/null | sed 's/^#//' | awk '{print $1}' | head -20; }
list_tz()     { find /usr/share/zoneinfo -type f ! -name "*.tab" 2>/dev/null | sed 's|/usr/share/zoneinfo/||' | sort | head -30; }

# Detect firmware packages needed for current hardware (lspci vendor IDs -> Arch split packages)
detect_firmware_packages() {
  local v pkg
  lspci -nn 2>/dev/null | sed -n 's/.*\[\([0-9a-f]*\):.*/\1/p' | tr '[:upper:]' '[:lower:]' | sort -u | while read -r v; do
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
      *)    ;;
    esac
  done | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# ---- UI ----
clear
show_logo
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- minimal arch install${NC}"
echo ""
log_info "Choose disk, hostname, user, password, locale and timezone."
echo ""

# Disk (numbered selection)
mapfile -t _disk_list < <(list_disks_raw)
[[ ${#_disk_list[@]} -eq 0 ]] && { log_err "No disks found"; exit 1; }
log_info "Disks:"
for i in "${!_disk_list[@]}"; do
  n=$((i+1)); name="${_disk_list[i]%% *}"; size="${_disk_list[i]#* }"
  echo "  ${n}) /dev/${name} (${size})"
done
echo ""
while true; do
  log_ask "Select disk (1-${#_disk_list[@]}): "
  read -r num </dev/tty
  num=$(echo "$num" | tr -d ' ')
  if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 && "$num" -le "${#_disk_list[@]}" ]]; then
    DISK="/dev/${_disk_list[$((num-1))]%% *}"
    log_warn "All data on ${DISK} will be erased."
    log_ask "Continue? (yes/no): "
    read -r c </dev/tty
    [[ "$c" =~ ^[Yy][Ee][Ss]$ ]] && break
  else
    log_err "Invalid choice (enter a number 1-${#_disk_list[@]})"
  fi
done

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
log_info "System language (LANG/locale): 1) Italian (it_IT.UTF-8)  2) English (en_US.UTF-8)  3) Custom"
log_ask "Choice (1-3, default 1): "
read -r lc </dev/tty
lc=${lc:-1}
case "$lc" in
  1) LOCALE="it_IT.UTF-8" ;;
  2) LOCALE="en_US.UTF-8" ;;
  3) log_info "Examples:"; list_locales; log_ask "Locale: "; read -r LOCALE </dev/tty ;;
  *) LOCALE="it_IT.UTF-8" ;;
esac

log_info "Keyboard layout: 1) Italian (it)  2) US (us)  3) Same as system language  4) German (de)  5) French (fr)  6) Spanish (es)  7) Custom"
log_ask "Choice (1-7, default 1): "
read -r km </dev/tty
km=${km:-1}
case "$km" in
  1) KEYMAP="it" ;;
  2) KEYMAP="us" ;;
  3) KEYMAP=$(keymap_for "$LOCALE") ;;
  4) KEYMAP="de" ;;
  5) KEYMAP="fr" ;;
  6) KEYMAP="es" ;;
  7) log_ask "Keymap (e.g. it, us): "; read -r KEYMAP </dev/tty; KEYMAP=$(echo "${KEYMAP:-us}" | tr -d ' '); [[ -z "$KEYMAP" ]] && KEYMAP="us" ;;
  *) KEYMAP="it" ;;
esac

log_info "Timezone: 1) Europe/Rome  2) Europe/London  3) America/New_York  4) Custom"
log_ask "Choice (1-4, default 1): "
read -r tz </dev/tty
tz=${tz:-1}
case "$tz" in
  1) TIMEZONE="Europe/Rome" ;;
  2) TIMEZONE="Europe/London" ;;
  3) TIMEZONE="America/New_York" ;;
  4) log_info "Examples:"; list_tz; log_ask "Timezone: "; read -r TIMEZONE </dev/tty ;;
  *) TIMEZONE="Europe/Rome" ;;
esac

# Mirror region: from locale or interactive
mirror_country_from_locale() {
  case "$1" in
    it_IT*) echo "IT" ;;
    en_US*) echo "US" ;;
    en_GB*) echo "GB" ;;
    de_DE*) echo "DE" ;;
    fr_FR*) echo "FR" ;;
    es_ES*) echo "ES" ;;
    *) echo "" ;;
  esac
}
echo ""
_mc=$(mirror_country_from_locale "$LOCALE"); _mclabel="${_mc:-all}"
log_info "Mirror region: 1) From locale (${LOCALE} -> ${_mclabel})  2) Italy  3) Germany  4) US  5) UK  6) All (no change)  7) Custom (2-letter code)"
log_ask "Choice (1-7, default 1): "
read -r mr </dev/tty
mr=${mr:-1}
case "$mr" in
  1) MIRROR_COUNTRY=$(mirror_country_from_locale "$LOCALE"); [[ -z "$MIRROR_COUNTRY" ]] && MIRROR_COUNTRY="all" ;;
  2) MIRROR_COUNTRY="IT" ;;
  3) MIRROR_COUNTRY="DE" ;;
  4) MIRROR_COUNTRY="US" ;;
  5) MIRROR_COUNTRY="GB" ;;
  6) MIRROR_COUNTRY="all" ;;
  7) log_ask "Country code (e.g. IT, FR): "; read -r MIRROR_COUNTRY </dev/tty; MIRROR_COUNTRY=$(echo "${MIRROR_COUNTRY:-all}" | tr '[:lower:]' '[:upper:]' | cut -c1-2); [[ -z "$MIRROR_COUNTRY" ]] && MIRROR_COUNTRY="all" ;;
  *) MIRROR_COUNTRY=$(mirror_country_from_locale "$LOCALE"); [[ -z "$MIRROR_COUNTRY" ]] && MIRROR_COUNTRY="all" ;;
esac

# Firmware: Full / Auto-detect / None
echo ""
log_info "Firmware: 1) Full (linux-firmware, ~700MB)  2) Auto (detect from this machine)  3) None (e.g. VM)"
log_ask "Choice (1-3, default 2): "
read -r fw </dev/tty
fw=${fw:-2}
case "$fw" in
  1) FIRMWARE_PACKAGES="linux-firmware" ;;
  2) FIRMWARE_PACKAGES=$(detect_firmware_packages); [[ -z "$FIRMWARE_PACKAGES" ]] && { log_warn "No hardware detected, using full firmware"; FIRMWARE_PACKAGES="linux-firmware"; } ;;
  3) FIRMWARE_PACKAGES="" ;;
  *) FIRMWARE_PACKAGES=$(detect_firmware_packages); [[ -z "$FIRMWARE_PACKAGES" ]] && FIRMWARE_PACKAGES="linux-firmware"; ;;
esac

echo ""
echo -e "  ${BOLD}Summary${NC}"
echo "  Disk:     ${DISK}"
echo "  Hostname: ${HOSTNAME}"
echo "  User:     ${USER}"
echo "  Locale:   ${LOCALE}"
echo "  Keymap:   ${KEYMAP}"
echo "  Timezone: ${TIMEZONE}"
echo "  Mirror:   ${MIRROR_COUNTRY}"
echo "  Firmware: ${FIRMWARE_PACKAGES:-none}"
echo ""
log_ask "Proceed? (yes/no): "
read -r confirm </dev/tty
[[ "$confirm" =~ ^[Yy][Ee][Ss]$ ]] || { log_err "Aborted"; exit 1; }

# Network check
log_info "Checking network..."
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null && ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
  log_err "No internet. Configure network first."
  exit 1
fi
log_ok "Network ok"

if [[ -n "$MIRROR_COUNTRY" && "$MIRROR_COUNTRY" != "all" ]]; then
  log_info "Updating mirrorlist for country: ${MIRROR_COUNTRY}"
  curl -sL "https://archlinux.org/mirrorlist/?country=${MIRROR_COUNTRY}&protocol=https&use_mirror_status=on" | sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
fi

pacman -Sy --noconfirm || true
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
loadkeys "${KEYMAP}" 2>/dev/null || true

# Partition: EFI 256MiB (was 512), rest root
log_info "Partitioning ${DISK} (EFI 256MiB + root)..."
parted -s "${DISK}" mklabel gpt
parted -s "${DISK}" mkpart primary fat32 1MiB 256MiB
parted -s "${DISK}" mkpart primary ext4 256MiB 100%
parted -s "${DISK}" set 1 esp on

if [[ "${DISK}" =~ nvme ]]; then
  BOOT_PART="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  BOOT_PART="${DISK}1"
  ROOT_PART="${DISK}2"
fi

log_info "Formatting..."
mkfs.fat -F32 "${BOOT_PART}"
mkfs.ext4 -F "${ROOT_PART}"

mount "${ROOT_PART}" /mnt
mkdir -p /mnt/boot
mount "${BOOT_PART}" /mnt/boot

log_info "Installing base system (minimal: base, linux, sudo, networkmanager, curl, grub)..."
BASE_PKGS="base linux sudo networkmanager curl grub efibootmgr"
[[ -n "$FIRMWARE_PACKAGES" ]] && BASE_PKGS="${BASE_PKGS} ${FIRMWARE_PACKAGES}"
pacstrap /mnt $BASE_PKGS
[[ -n "$MIRROR_COUNTRY" && "$MIRROR_COUNTRY" != "all" ]] && cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
pacman -Scc --noconfirm 2>/dev/null || true

genfstab -U /mnt > /mnt/etc/fstab

# Escape locale for sed (computed in host shell so heredoc expansion has it)
_LOCALE_ESC="${LOCALE//./\\.}"

log_info "Configuring system..."
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
# Enable only the selected locale (no extra en_US unless that is the chosen one)
sed -i "/^#${_LOCALE_ESC}/s/^#//" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   %s.localdomain %s\n' "${HOSTNAME}" "${HOSTNAME}" > /etc/hosts
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
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

mkdir -p /mnt/home/${USER}/.config /mnt/home/${USER}/.local/bin /mnt/home/${USER}/.cache
uid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f3)
gid=$(grep "^${USER}:" /mnt/etc/passwd | cut -d: -f4)
[[ -n "$uid" && -n "$gid" ]] && chown -R "${uid}:${gid}" /mnt/home/${USER}

log_info "Unmounting..."
umount -R /mnt

echo ""
log_ok "Install done."
echo ""
echo "  Next:"
echo "    1. reboot"
echo "    2. Log in as ${USER}"
echo "    3. Run:  curl -fsSL https://pages.acridite.cc/minidite/setup | bash"
echo "    4. In setup you can install OpenSSH and configure SSH keys"
echo ""
