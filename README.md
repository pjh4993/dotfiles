# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Config |
|---------|--------|
| **nvim** | Neovim (LazyVim) |
| **tmux** | tmux |
| **alacritty** | Alacritty terminal |
| **zsh** | Zsh shell |
| **git** | Git |
| **aerospace** | AeroSpace window manager |
| **lazygit** | LazyGit |

## Setup

```bash
# Install GNU Stow
brew install stow  # macOS

# Clone and apply
git clone https://github.com/pjh4993/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Stow all packages
stow nvim alacritty tmux zsh git aerospace lazygit

# Or selectively
stow nvim tmux
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
