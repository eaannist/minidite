```
██▄  ▄██ ▄▄ ▄▄  ▄▄ ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄▄ ▄▄▄▄▄ 
██ ▀▀ ██ ██ ███▄██ ██ ██▀██ ██   ██   ██▄▄  
██    ██ ██ ██ ▀██ ██ ████▀ ██   ██   ██▄▄▄ 
```

Minimal Arch Linux server: interactive install and setup. Kept as light as possible; OpenSSH and extra tools are optional in setup.

## Features

- **install.sh** (from [Arch ISO](https://archlinux.org/download/), root): minimal base only (base, linux, sudo, networkmanager, curl, grub; optional firmware; no openssh/git). Mirror region and single locale. See [install.sh](#installsh) below.
- **setup.sh** (after first login, user): optional CLI packages, configs, optional OpenSSH server and SSH key setup, optional Docker/Podman. Re-run asks before overwriting configs. See [setup.sh](#setupsh) below.

## Quick start

```bash
# 1. Install (Arch ISO, root)
curl -fsSL https://pages.acridite.cc/minidite/install | bash

# 2. Reboot, then (as user)
curl -fsSL https://pages.acridite.cc/minidite/setup | bash
exec bash
```

## install.sh

Run once as **root** from an Arch Linux live ISO. It performs a minimal installation on a single disk.

**What it does:**

1. **Interactive prompts:** disk (with confirmation), hostname, username, password, locale (it_IT / en_US / custom), timezone (Europe/Rome, Europe/London, America/New_York, or custom), mirror region (from locale or Italy/Germany/US/UK/custom), firmware (full / auto-detect from hardware / none). Summary and final confirm before proceeding.
2. **Network check:** verifies connectivity (ping) before installing.
3. **Mirrorlist:** if a country was chosen, downloads mirrorlist for that country (HTTPS, mirror status) and uses it for pacman.
4. **Partitioning:** GPT table, EFI partition 256 MiB (FAT32), remaining space as single root partition (ext4). ESP flag set on EFI.
5. **Base install:** `pacstrap` with the minimal package list below (firmware only if selected).
6. **Chroot configuration:** timezone, single locale in locale.gen (only the one chosen), LANG/LC_COLLATE, vconsole KEYMAP, hostname, `/etc/hosts`, GRUB (EFI), `systemctl enable` for NetworkManager only. User created with wheel, bash as shell, sudo NOPASSWD. `~/.ssh` created and permissions set (for later use by setup). Root shell set to bash. Pacman cache cleared in chroot.
7. **Directories:** creates `~/.config`, `~/.local/bin`, `~/.cache` for the new user and sets ownership.
8. **Unmount** and prints next steps (reboot, login, run setup; OpenSSH can be installed in setup).

**Packages installed (pacstrap):**

| Package | Purpose |
|---------|--------|
| base | Core system |
| linux | Kernel |
| linux-firmware (or split) | Optional: full, auto-detect from lspci, or none |
| sudo | Privilege escalation |
| networkmanager | Networking |
| curl | HTTP client (for setup bootstrap) |
| grub | Bootloader |
| efibootmgr | EFI boot management |

---

## setup.sh

Run as **normal user** after first login (after install.sh and reboot). Optional CLI packages, configs, optional OpenSSH server and SSH keys, optional Docker/Podman.

**What it does:**

1. **Packages (optional):** asks whether to install recommended CLI tools (micro, btop, zoxide, fzf, ripgrep, eza, unzip, tree, nerd font, fastfetch). Skip for a minimal install (configs only).
2. **Directories:** ensures `~/.config/oh-my-posh`, `~/.config/micro`, `~/.config/fastfetch`, `~/.config/fzf`, `~/.local/bin`, `~/.cache/bash` exist.
3. **Configs:** downloads from repo `home/` into `$HOME` (`.bashrc`, theme.omp.json, micro/fastfetch configs, minidite-version). If setup was already run (detected via "minidite" in `.bashrc`), asks before overwriting.
4. **OpenSSH server (optional):** asks to install and configure OpenSSH; if yes, installs openssh, appends ClientAliveInterval/etc. to `sshd_config`, enables and starts sshd.
5. **SSH keys:** if no key exists, offers to generate `id_ed25519` and add to `authorized_keys`. If key exists but `authorized_keys` is empty, offers to add it. If both present, step is skipped.
6. **Optional Docker:** install Docker (engine + compose), enable docker.service, add user to group docker.
7. **Optional Podman:** install Podman via pacman.
8. **Oh My Posh:** if the binary is missing, install to `~/.local/bin` via the official script.

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
| **Network** | ip, ipa, ipr | ip with colors |
| | ping | 4 packets |
| | ports | Listening ports (ss -tulpn) |
| | ipp | Public IP address |
| | ipl | Local IP address |

## Links

- **Bootstrap:** https://pages.acridite.cc/minidite/install and https://pages.acridite.cc/minidite/setup
- **Repo:** https://github.com/eaannist/minidite

MIT.
