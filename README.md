# dotfiles

Personal shell configuration for **Arch / EndeavourOS** with KDE Plasma + Zsh.

All files are managed as symlinks from this repository to their expected locations. The structure mirrors the home directory — files at the repo root go to `~/`, and subdirectories mirror their counterparts.

---

## Repository Structure

```
.
├── .bash_profile          → ~/.bash_profile
├── .bashrc                → ~/.bashrc
├── .bash_logout           → ~/.bash_logout
├── .zshrc                 → ~/.zshrc
├── .wezterm.lua           → ~/.wezterm.lua
│
├── .bin/
│   ├── FullUpgrade.py      → ~/.local/bin/FullUpgrade
│   ├── nvims.sh            → ~/.local/bin/nvims
│   ├── pdfs.sh             → ~/.local/bin/pdfs
│   └── htmls.sh            → ~/.local/bin/htmls
│
├── .crucial/              (package management & system config)
│   ├── command_to_install.txt
│   ├── Explicit_pkg.list
│   ├── missing.sh
│   ├── nerdfont_install.sh
│   ├── pacman.conf
│   ├── pkg.list
│   └── uninstall.sh
│
└── .custom/               → ~/.custom/
    ├── start.sh
    ├── aliases_set.sh
    ├── exports.sh
    ├── zsh_imports_zinit.sh
    └── set_ufw/
        ├── set_ufw_permissions.sh
        ├── clear.sh
        ├── home.sh
        ├── public.sh
        └── work.sh
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/Ren-B-7/dotfiles.git ~/dotfiles
cd ~/Documents/dotfiles
```

### 2. Create symlinks

```bash
# Shell config
ln -sf ~/Documents/dotfiles/.zshrc           ~/.zshrc
ln -sf ~/Documents/dotfiles/.bashrc          ~/.bashrc
ln -sf ~/Documents/dotfiles/.bash_profile    ~/.bash_profile
ln -sf ~/Documents/dotfiles/.wezterm.lua     ~/.wezterm.lua
ln -sf ~/Documents/dotfiles/.bash_logout     ~/.bash_logout

# Binaries
mkdir -p ~/.local/bin
ln -sf ~/Documents/dotfiles/.bin/FullUpgrade.sh     ~/.local/bin/FullUpgrade
ln -sf ~/Documents/dotfiles/.bin/nvims.sh           ~/.local/bin/nvims
ln -sf ~/Documents/dotfiles/.bin/pdfs.sh            ~/.local/bin/pdfs
ln -sf ~/Documents/dotfiles/.bin/htmls.sh           ~/.local/bin/htmls
chmod +x ~/Documents/dotfiles/.bin/FullUpgrade.sh ~/Documents/dotfiles/.bin/nvims.sh ~/Documents/dotfiles/.bin/pdfs.sh ~/Documents/dotfiles/.bin/htmls.sh
```

---

## Files

### Shell Entry Points

**`.zshrc`** — Main Zsh config. Resolves its own real path via `${(%):-%x}:A`, so `IMPORTS` always points to `.custom/` relative to where the dotfiles repo lives — no hardcoded paths needed. Loads Powerlevel10k instant prompt, then sources `zsh_imports_zinit.sh` and `start.sh`.

**`.bashrc` / `.bash_profile`** — Bash equivalents. `.bash_profile` sources `.bashrc` for login shells.

**`.bash_logout`** — Empty. Present to prevent errors in environments that expect it.

### `.custom/` — Shell Scripts

Sourced at shell startup via `start.sh`. The `IMPORTS` env var is set by `.zshrc`/`.bashrc` to point to this directory automatically — resolved from the symlink's real path, so no manual configuration is needed.

| File                     | Description                                                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `start.sh`               | Entry point — sources all other scripts in this directory                                                                                                  |
| `exports.sh`             | Sets `PATH` (Cargo, Mason LSPs, pip), `LANG`, and starts `ssh-agent` if not running                                                                        |
| `aliases_set.sh`         | Aliases: Neovim configs (`cvim`, `xvim`, `svim`, `tvim`), system commands, `ls`, navigation shortcuts, `trash`-aware `rm`                                  |
| `zsh_imports_zinit.sh`   | Installs Zinit if missing, loads plugins (autosuggestions, completions, syntax highlighting, Powerlevel10k), OMZ snippets, and configures history & zoxide |
| `set_ufw_permissions.sh` | `ufwSet()` — fzf menu to switch UFW firewall profile (Public / Home / Work / Clear backups)                                                                |
| `set_ufw/public.sh`      | UFW profile: SSH, HTTP, HTTPS only                                                                                                                         |
| `set_ufw/home.sh`        | UFW profile: local network access + MySQL, web servers, VNC                                                                                                |
| `set_ufw/work.sh`        | UFW profile: SSH, HTTP/S, dev servers, MySQL, PostgreSQL, VNC, Flask                                                                                       |
| `set_ufw/clear.sh`       | Removes UFW backup rule files from `/etc/ufw/`                                                                                                             |

### `.bin/`

| File             | Symlink target             | Description                                            |
| ---------------- | -------------------------- | ------------------------------------------------------ |
| `FullUpgrade`    | `~/.local/bin/FullUpgrade` | Interactive full system upgrade script (see below)     |
| `nvims`          | `~/.local/bin/nvims`       | fzf picker to launch Neovim with a selected config     |
| `pdfs`           | `~/.local/bin/pdfs`        | fzf file browser that opens PDFs with `xdg-open`       |
| `htmls`          | `~/.local/bin/htmls`       | fzf file browser that opens HTML files with `xdg-open` |

Also available as the `FullUpgrade` alias.

#### FullUpgrade.py

An interactive Python script for Arch/EndeavourOS system maintenance. Run with `sudo` (auto-elevates if needed). Steps:

1. **Mirrorlist** — Downloads and ranks the fastest Arch and EndeavourOS mirrors in parallel using `rankmirrors`
2. **fwupd** — Firmware updates via `fwupdmgr`
3. **pacman** — Full system upgrade with `pacman -Syu`
4. **yay** — AUR upgrade
5. **Flatpak** — Updates all installed Flatpaks
6. **Zinit** — Updates Zsh plugins
7. **Journalctl / logs** — Optional log vacuuming, log file truncation, and coredump cleanup
8. **Reboot** — Optional reboot prompt at the end

Each step is interactive with yes/no prompts and can be skipped.

### `.crucial/` — System Reference Files

Not symlinked anywhere — kept as reference and used manually.

| File                     | Description                                                                                                                                        |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pkglist.list`           | Full list of all installed pacman packages                                                                                                         |
| `Explicit_pkg.list`      | Explicitly installed packages only (not pulled in as dependencies)                                                                                 |
| `command_to_install.txt` | Commands to reproduce the full package set on a fresh install                                                                                      |
| `pacman.conf`            | Snapshot of `/etc/pacman.conf` (includes Chaotic-AUR)                                                                                              |
| `uninstall.sh`           | Removes any installed package not present in a given whitelist file — useful for cleaning up after restoring from `pkglist.list`                   |
| `missing.sh`             | Compares two lists and prints packages from the first that are absent in the second                                                                |
| `nerdfont_install.sh`    | Clones the Nerd Fonts repo with sparse checkout, installs all patched fonts to `~/.local/share/fonts`, then cleans up and refreshes the font cache |

#### Restoring packages on a fresh install

```bash
sudo pacman -S --needed - < .crucial/pkg.list
```

#### Removing unlisted packages

```bash
./.crucial/uninstall.sh .crucial/pkglist.list
```

#### Checking for missing packages

```bash
./.crucial/missing.sh .crucial/Explicit_pkg.list <(pacman -Qqe)
```

### `.wezterm.lua`

WezTerm terminal configuration:

- Transparent background (60% opacity)
- WebGPU renderer at low power
- 120 fps, 120 Hz cursor blink
- Custom font: Roboto Mono Nerd Font (from `~/.local/share/fonts/NerdFonts`)
- Flat (base16) colour scheme
- No title bar (resize-only decorations)
- Zero padding
- Runs `fastfetch` on first window open
- ALT-based keybindings for pane splitting, tab navigation, and window management

---

## Dependencies

The following tools must be installed for full functionality:

- `zsh`, `zoxide`, `fzf` — core shell experience
- `neovim` — editor (multiple configs supported)
- `ufw` — firewall management
- `wezterm` — terminal emulator
- `fastfetch` — system info display
- `trash-cli` — safe `rm` replacement
- `zinit` — installed automatically by `zsh_imports_zinit.sh` on first shell launch
- `rankmirrors` (`pacman-contrib`) — used by `FullUpgrade.py`

---

## Neovim Configs

Four Neovim configurations are supported, selected via `nvims` or launched directly with an alias:

| Alias  | Config name       | Description                             |
| ------ | ----------------- | --------------------------------------- |
| `tvim` | `Tiny.nvim`       | Minimal                                 |
| `svim` | `Simplicity.nvim` | Light                                   |
| `xvim` | `Simplexity.nvim` | Balanced (Mason LSPs sourced from here) |
| `cvim` | `Complexity.nvim` | Full-featured                           |

Each config lives in `~/.config/<ConfigName>/` per the `NVIM_APPNAME` convention.
