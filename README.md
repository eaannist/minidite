```
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
```

Minimal Arch Linux server: interactive install and setup. Kept as light as possible; OpenSSH and extra tools are optional in setup.

## Features

- **install.sh** (from [Arch ISO](https://archlinux.org/download/), root): minimal base only (base, linux, sudo, networkmanager, curl, **Limine**, **Snapper**; optional firmware; no openssh). Single Btrfs root (@) with @snapshots, Limine bootloader with custom theme. Snapper is installed but configured in setup. See [install.sh](#installsh) below.
- **setup.sh** (after first login, user): optional CLI packages, configs, optional OpenSSH, SSH keys (server + client, optional password disable), Docker/Podman, **Snapper config** (1 daily snapshot at 4am, max 5 total), **Limine snapshot menu** (tree: Minidite > linux, Snapshots). Re-run asks before overwriting configs. See [setup.sh](#setupsh) below.

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
5. **Btrfs:** root partition formatted Btrfs; subvolumes **`@`** (root; includes /home, /var) and **`@snapshots`** (for Snapper). Mount options: `compress=zstd:1`, `space_cache=v2`, `noatime`, `discard=async`, `ssd`, `commit=120`. No reserved blocks.
6. **Base install:** `pacstrap` (cache on target; cleared in chroot), minimal package list below (firmware only if selected).
7. **Chroot configuration:** timezone, single locale, KEYMAP, hostname, `/etc/hosts`, journald 50M limit, **Limine** (ESP at `/boot`, `limine.conf` with tree menu, custom theme black/yellow/cyan, `rootflags=subvol=@`; kernel and initramfs on ESP), `mkinitcpio -P` with btrfs in MODULES and udev-based HOOKS, NetworkManager, user, sudo, `~/.ssh`. Snapper is installed but not configured (setup does that). Pacman cache cleared in chroot.
8. **Directories:** creates `~/.config`, `~/.local/bin`, `~/.cache` for the new user and ownership.
9. **Unmount** and next steps (reboot, login, run setup).

**Btrfs layout:** Single active subvolume **@** for / (includes /home, /var). **@snapshots** is mounted at `/.snapshots`. Snapper (configured in setup) stores max 5 snapshots (1 daily at 4am + manual). **Limine** is used instead of GRUB; ESP at `/boot` (FAT) so kernel and initramfs are on the ESP for Limine to load. Custom theme: black background, light yellow foreground, cyan accent.

**Disk usage:** (1) No 5% reserved. (2) Compression zstd:1. (3) Max 5 snapshots total. (4) Firmware, pacman cache, journal 50M.

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
| snapper | Root snapshot management (configured in setup) |
| btrfs-progs | Btrfs tools and fsck |
| efibootmgr | EFI boot entry (Limine) |

---

## setup.sh

Run as **normal user** after first login (after install.sh and reboot). Optional CLI packages, configs, optional OpenSSH server and SSH keys, optional Docker/Podman.

**What it does:**

1. **Packages (optional):** install recommended CLI tools (micro, btop, zoxide, fzf, ripgrep, eza, unzip, tree, nerd font, fastfetch).
2. **Directories:** ensures `~/.config/oh-my-posh`, `~/.config/micro`, `~/.config/fastfetch`, `~/.config/fzf`, `~/.local/bin`, `~/.cache/bash` exist.
3. **Configs:** downloads from repo `home/` into `$HOME` (`.bashrc`, theme.omp.json, micro/fastfetch configs, minidite-version). Copies minidite-version to `/etc` for bootloader. Asks before overwriting if already run.
4. **OpenSSH (optional):** install and harden (PermitRootLogin no, MaxAuthTries 3, drop-in configs).
5. **SSH keys:** server key (for outgoing connections); client key (paste your PC's public key for remote login); optional disable password auth (only after client key is in authorized_keys). Use `ssh-lockdown` / `ssh-unlock` later.
6. **Snapper (optional):** if `/.snapshots` exists, configure root: 1 daily snapshot at 4am, max 5 total (manual + auto), `snapper-cleanup.timer` enabled.
7. **Limine snapshot menu (optional):** install `/usr/local/bin/limine-snapper-menu.sh`; regenerates boot menu with tree (Minidite > linux, Snapshots > entries); daily cron at 3am; version in branding.
8. **Docker (optional):** engine + compose, docker.service, user in docker group.
9. **Podman (optional):** rootless setup, podman.socket.
10. **Lazydocker (optional):** TUI to `~/.local/bin` if Docker/Podman present.
11. **Oh My Posh (optional):** install to `~/.local/bin`.
12. **Cleanup:** pacman cache cleared, orphans removed, fstrim.timer, paccache.timer.

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
| **System** | sysinfo | fastfetch with custom logo |
| | reboot, poweroff, shutdown | sudo wrapper |
| **Snapshot** | snap [desc] | Create manual snapshot; update Limine menu |
| | snap-ls | List snapshots |
| | snap-diff \<num\> | Diff snapshot vs current |
| | snap-rm \<num\> | Delete snapshot |
| | snap-rollback \<num\> | Rollback root to snapshot (reboot required) |
| **SSH** | ssh-lockdown | Disable password auth (key-only) |
| | ssh-unlock | Re-enable password auth |
| **Lazydocker** | ld-podman | Set DOCKER_HOST to Podman socket |
| | ld-reset | Unset DOCKER_HOST (use Docker) |
| **Network** | ip, ipa, ipr | ip with colors |
| | ping | 4 packets |
| | ports | Listening ports (ss -tulpn) |
| | ipp | Public IP address |

## Links

- **Install:** https://x.acridite.cc/minidite/install
- **Setup:** https://x.acridite.cc/minidite/setup
- **Repo:** https://github.com/eaannist/minidite

MIT.
