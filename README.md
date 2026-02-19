```
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
```

Minimal Arch Linux server: interactive install and setup. Kept as light as possible; OpenSSH and extra tools are optional in setup.

## Features

- **install.sh** (from [Arch ISO](https://archlinux.org/download/), root): minimal base only (base, linux, sudo, networkmanager, curl, **Limine**, **Snapper**; optional firmware; no openssh/git). Single Btrfs root (@) with @snapshots, Limine bootloader, Snapper for timeline snapshots. See [install.sh](#installsh) below.
- **setup.sh** (after first login, user): optional CLI packages, configs, optional OpenSSH, SSH keys, Docker/Podman, **Limine snapshot menu** (boot menu with snapshots). Re-run asks before overwriting configs. See [setup.sh](#setupsh) below.

## Quick start

```bash
# 1. Install (Arch ISO, root)
curl -fsSL x.acridite.cc/minidite/install | bash

# 2. Reboot, then (as user)
curl -fsSL x.acridite.cc/minidite/setup | bash
exec bash
```

## install.sh

Run once as **root** from an Arch Linux live ISO. It performs a minimal installation on a single disk.

**What it does:**

1. **Interactive prompts:** disk (with confirmation), hostname, username, password, locale (it_IT / en_US / custom), timezone (Europe/Rome, Europe/London, America/New_York, or custom), mirror region (from locale or Italy/Germany/US/UK/custom), firmware (full / auto-detect from hardware / none). Summary and final confirm before proceeding.
2. **Network check:** verifies connectivity (ping) before installing.
3. **Mirrorlist:** if a country was chosen, downloads mirrorlist for that country (HTTPS, mirror status) and uses it for pacman.
4. **Partitioning:** GPT table, EFI partition **512 MiB** (FAT32), remaining space as single root partition (Btrfs). ESP flag set on EFI.
5. **Btrfs:** root partition is formatted Btrfs; subvolumes **`@`** (root only; includes /home and /var) and **`@snapshots`** (for Snapper). Mount options: `compress=zstd:1`, `space_cache=v2`, `noatime`, `discard=async`, `ssd`, `commit=120`. No reserved blocks; Btrfs quota enabled with limit on `/.snapshots`.
6. **Base install:** `pacstrap` (cache on target; cleared in chroot), minimal package list below (firmware only if selected).
7. **Chroot configuration:** timezone, single locale, KEYMAP, hostname, `/etc/hosts`, journald 50M limit, **Limine** (ESP mounted at `/boot`, limine.cfg with root entry using `rootflags=subvol=@`; kernel and initramfs on ESP so Limine can read them), `mkinitcpio -P` with btrfs in MODULES and HOOKS, NetworkManager, user, sudo, `~/.ssh`. **Snapper** config `root`: timeline daily, 5 kept, NUMBER_LIMIT 5–10. Pacman cache cleared in chroot.
8. **Directories:** creates `~/.config`, `~/.local/bin`, `~/.cache` for the new user and ownership.
9. **Unmount** and next steps (reboot, login, run setup).

**Btrfs layout:** Single active subvolume **@** for / (includes /home, /var). **@snapshots** is mounted at `/.snapshots` with quota limit (e.g. 20G). Snapper stores timeline and manual snapshots there. **Limine** is used instead of GRUB; ESP is mounted at `/boot` (FAT) so kernel and initramfs are on the ESP for Limine to load.

**Disk usage and what to expect:** (1) **No 5% reserved** – full partition usable. (2) **Compression** zstd:1 – good space savings. (3) **Snapshots** – 5 timeline + manual; reserve ~15–20% disk for snapshot buffer. (4) Firmware, pacman cache, journal 50M as before.

**Packages installed (pacstrap):**

| Package | Purpose |
|---------|--------|
| base | Core system |
| linux | Kernel |
| linux-firmware (or split) | Optional: full, auto-detect from lspci, or none |
| sudo | Privilege escalation |
| networkmanager | Networking |
| curl | HTTP client (for setup bootstrap) |
| limine | Bootloader (replaces GRUB) |
| snapper | Root snapshot management (timeline + manual) |
| btrfs-progs | Btrfs tools and fsck |
| efibootmgr | EFI boot entry (Limine) |

---

## setup.sh

Run as **normal user** after first login (after install.sh and reboot). Optional CLI packages, configs, optional OpenSSH server and SSH keys, optional Docker/Podman.

**What it does:**

1. **Packages (optional):** asks whether to install recommended CLI tools (micro, btop, zoxide, fzf, ripgrep, eza, unzip, tree, nerd font, fastfetch). Skip for a minimal install (configs only).
2. **Directories:** ensures `~/.config/oh-my-posh`, `~/.config/micro`, `~/.config/fastfetch`, `~/.config/fzf`, `~/.local/bin`, `~/.cache/bash` exist.
3. **Configs:** downloads from repo `home/` into `$HOME` (`.bashrc`, theme.omp.json, micro/fastfetch configs, minidite-version). If setup was already run (detected via "minidite" in `.bashrc`), asks before overwriting.
4. **OpenSSH server (optional):** asks to install and configure OpenSSH; if yes, installs openssh, appends ClientAliveInterval/etc. to `sshd_config`, enables and starts sshd.
5. **SSH keys:** if no key exists, offers to generate `id_ed25519` and add to `authorized_keys`. If key exists but `authorized_keys` is empty, offers to add it. If both present, step is skipped.
6. **Optional Docker:** install Docker (engine + compose), enable docker.service, add user to group docker; if Docker is installed, lazydocker (TUI) is installed to `~/.local/bin`.
7. **Optional Podman:** install Podman; post-install: unqualified-search registries (docker.io), subuid/subgid for rootless if missing, user socket (podman.socket) for Docker-compatible API.
8. **Lazydocker (optional):** if Docker or Podman is installed, offers to install lazydocker to `~/.local/bin`.
9. **Limine snapshot menu (optional):** if Snapper and `/.snapshots` exist, offers to install a script that regenerates the Limine boot menu with current root and all snapshots (so you can boot a snapshot from the menu). Installs `/usr/local/bin/limine-snapper-menu.sh` and a daily cron (3am).
10. **Oh My Posh:** if the binary is missing, install to `~/.local/bin` via the official script.
11. **Pacman cache:** cleared at end to free disk space.
12. **Post-setup:** orphan packages removed, `fstrim.timer` enabled (weekly TRIM), `paccache.timer` enabled if pacman-contrib is installed.

**Packages installed (pacman):**

| Package | Purpose |
|---------|--------|
| micro | Text editor |
| btop | System monitor |
| zoxide | Smart cd |
| fzf | Fuzzy finder |
| ripgrep | Fast grep (rg) |
| eza | Modern ls |
| unzip | Extract archives |
| tree | Directory tree |
| ttf-firacode-nerd | Nerd Font for prompt and eza |
| fastfetch | System info with custom logo |

---

## Commands, aliases, functions (bash)

| Category | Item | Description |
|----------|------|-------------|
| **Profile** | profile-edit | Edit .bashrc |
| | theme-edit | Edit Oh My Posh theme |
| | reload | Reload bash |
| | show-help | Full command reference |
| **Dirs** | b, bb, bbb | Up 1, 2, 3 directories |
| | mkcd \<dir\> | Create dir and cd into it |
| | ls, ll, la, lt, l | eza list (icons; la0 = no icons) |
| **Files** | nf \<file\> | Create file and open in editor (micro) |
| | head \<file\> [n] | First n lines (default 10) |
| | tail \<file\> [n] | Last n lines; tail -f supported |
| | extract \<archive\> | Extract .tar.gz, .zip, .tar.xz, etc. |
| **FZF** | f | Run fzf |
| | cdf | Cd into directory (fuzzy pick) |
| | ff | Fuzzy find file (e.g. micro \$(ff)) |
| | (key bindings) | Ctrl+R history, Ctrl+T files, Alt+C cd |
| **Git** | g, ga, gaa | git, add, add --all |
| | gb, gc, gca, gco | branch, commit, amend, checkout |
| | gd, gl, gla | diff, log, log --all |
| | gp, gpl | push, pull |
| | gs, gst, gstp, gsw | status, stash, stash pop, switch |
| | gu-set \<name\> | Set git user.name |
| | gu-get | Show git user and email |
| **System** | sysinfo | fastfetch with custom logo |
| | reboot, poweroff, shutdown | sudo wrapper |
| **Snapshot** | snap | create manual root snapshot (Snapper); update Limine menu if script present |
| **Network** | ip, ipa, ipr | ip with colors |
| | ping | 4 packets |
| | ports | Listening ports (ss -tulpn) |
| | ipp | Public IP address |
| | ipl | Local IP address |

## Links

- **Install:** https://x.acridite.cc/minidite/install
- **Setup:** https://x.acridite.cc/minidite/setup
- **Repo:** https://github.com/eaannist/minidite

MIT.
