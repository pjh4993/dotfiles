# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Config | OS | Notes |
|---------|--------|----|-------|
| **nvim** | Neovim (LazyVim) | Both | |
| **tmux** | tmux | Both | |
| **alacritty** | Alacritty terminal | Both | GUI only |
| **zsh** | Zsh shell | Both | |
| **git** | Git | Both | |
| **lazygit** | LazyGit | Both | |
| **aerospace** | AeroSpace window manager | macOS only | |
| **i3** | i3 window manager | Linux only | GUI only |

## Quick Setup

```bash
git clone https://github.com/pjh4993/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The install script automatically detects your OS and:
- Installs dependencies via `brew` (macOS) or `apt` (Linux)
- Installs CLI tools: direnv, git-delta, broot, ripgrep, fd, jq, lazysql, carbonyl
- Stows the correct packages (skips aerospace on Linux, skips i3 on macOS)

### Linux Server (Headless)

For servers without a display, use the `--server` flag to skip GUI packages (alacritty, i3, xclip, fonts):

```bash
./install.sh --server
```

## Manual Setup

### macOS

```bash
brew install stow
cd ~/dotfiles
stow nvim alacritty tmux zsh git aerospace lazygit
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install stow
cd ~/dotfiles
stow nvim alacritty tmux zsh git i3 lazygit
```

### Linux Server (Headless)

```bash
sudo apt install stow
cd ~/dotfiles
stow nvim tmux zsh git lazygit
```

## Adding a new config

```bash
mkdir -p ~/dotfiles/<name>/.config/<name>
mv ~/.config/<name>/* ~/dotfiles/<name>/.config/<name>/
cd ~/dotfiles && stow <name>
```

## Removing a package

```bash
cd ~/dotfiles && stow -D <name>
```
