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

[[ $EUID -eq 0 ]] || { log_err "Run as root"; exit 1; }

list_disks()  { lsblk -d -n -o NAME,SIZE,TYPE | grep -E 'disk|nvme' | awk '{print "/dev/" $1 " (" $2 ")"}'; }
valid_disk()  { [[ -b "$1" ]] && lsblk -d -n -o NAME "$1" &>/dev/null; }
valid_user()  { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#1} -ge 3 && ${#1} -le 32 ]]; }
valid_host()  { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] && [[ ${#1} -le 63 ]]; }
keymap_for()  { case "$1" in *it_IT*) echo it;; *en_US*) echo us;; *de_DE*) echo de;; *fr_FR*) echo fr;; *es_ES*) echo es;; *) echo us;; esac; }
list_locales(){ grep -E '^#?[a-z]{2}_[A-Z]{2}\.UTF-8' /etc/locale.gen 2>/dev/null | sed 's/^#//' | awk '{print $1}' | head -20; }
list_tz()     { find /usr/share/zoneinfo -type f ! -name "*.tab" 2>/dev/null | sed 's|/usr/share/zoneinfo/||' | sort | head -30; }

# ---- UI ----
clear
show_logo
echo -e "  ${BOLD}minidite${NC}  ${DIM}-- minimal arch install${NC}"
echo ""
log_info "Choose disk, hostname, user, password, locale and timezone."
echo ""

# Disk
log_info "Disks:"
list_disks
echo ""
while true; do
  log_ask "Disk to use (e.g. /dev/sda): "
  read -r DISK </dev/tty
  DISK=$(echo "$DISK" | tr -d ' ')
  if valid_disk "$DISK"; then
    log_warn "All data on ${DISK} will be erased."
    log_ask "Continue? (yes/no): "
    read -r c </dev/tty
    [[ "$c" =~ ^[Yy][Ee][Ss]$ ]] && break
  else
    log_err "Invalid disk"
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
log_info "Locale: 1) it_IT.UTF-8  2) en_US.UTF-8  3) Custom"
log_ask "Choice (1-3, default 1): "
read -r lc </dev/tty
lc=${lc:-1}
case "$lc" in
  1) LOCALE="it_IT.UTF-8" ;;
  2) LOCALE="en_US.UTF-8" ;;
  3) log_info "Examples:"; list_locales; log_ask "Locale: "; read -r LOCALE </dev/tty ;;
  *) LOCALE="it_IT.UTF-8" ;;
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

KEYMAP=$(keymap_for "$LOCALE")

echo ""
echo -e "  ${BOLD}Summary${NC}"
echo "  Disk:     ${DISK}"
echo "  Hostname: ${HOSTNAME}"
echo "  User:     ${USER}"
echo "  Locale:   ${LOCALE}"
echo "  Timezone: ${TIMEZONE}"
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

log_info "Installing base system..."
pacstrap /mnt base linux linux-firmware openssh sudo git zsh bash networkmanager curl grub efibootmgr
pacman -Scc --noconfirm 2>/dev/null || true

genfstab -U /mnt > /mnt/etc/fstab

log_info "Configuring system..."
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i '/^#${LOCALE}/s/^#//' /etc/locale.gen
sed -i '/^#en_US.UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   %s.localdomain %s\n' "${HOSTNAME}" "${HOSTNAME}" > /etc/hosts
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager.service sshd.service
useradd -m -G wheel -s /bin/zsh "${USER}"
echo "${USER}:${PASSWORD}" | chpasswd
echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER}
chmod 0440 /etc/sudoers.d/${USER}
mkdir -p /home/${USER}/.ssh
chmod 700 /home/${USER}/.ssh
chown -R ${USER}:${USER} /home/${USER}
printf '\n# minidite / Cursor\nClientAliveInterval 60\nClientAliveCountMax 3\nTCPKeepAlive yes\nCompression yes\n' >> /etc/ssh/sshd_config
chsh -s /bin/zsh root 2>/dev/null || true
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
echo "    4. Add your SSH key to ~/.ssh/authorized_keys if needed"
echo ""
