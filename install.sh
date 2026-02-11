#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_PACKAGES=(nvim tmux zsh git lazygit)

HEADLESS=false
for arg in "$@"; do
  case "$arg" in
    --server|--headless) HEADLESS=true ;;
  esac
done

install_macos() {
  echo "==> Detected macOS"

  if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  echo "==> Installing dependencies..."
  brew install stow neovim tmux alacritty zsh git lazygit direnv git-delta broot ripgrep
  brew install --cask nikitabobko/tap/aerospace
  gem install tmuxinator

  echo "==> Stowing packages..."
  cd "$DOTFILES_DIR"
  stow "${BASE_PACKAGES[@]}" alacritty aerospace tmuxinator
}

install_linux() {
  echo "==> Detected Linux (Ubuntu/Debian)"

  echo "==> Installing dependencies..."
  sudo apt update
  sudo apt install -y stow tmux zsh git direnv curl unzip ripgrep

  if [ "$HEADLESS" = false ]; then
    sudo apt install -y i3 i3status xclip
  fi

  # Install alacritty if not present (GUI only)
  if [ "$HEADLESS" = false ] && ! command -v alacritty &>/dev/null; then
    echo "==> Installing Alacritty via snap..."
    sudo snap install alacritty --classic 2>/dev/null || echo "    Snap not available, install Alacritty manually"
  fi

  # Install neovim from GitHub releases (apt version is too old for LazyVim)
  if ! command -v nvim &>/dev/null || [[ "$(printf '%s\n' "$(nvim --version | head -1 | grep -oP '\d+\.\d+\.\d+')" 0.11.2 | sort -V | head -1)" != "0.11.2" ]]; then
    echo "==> Installing Neovim (>= 0.11.2 required)..."
    curl -fLo /tmp/nvim-linux-x86_64.tar.gz https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    sudo rm -rf /opt/nvim-linux-x86_64
    sudo tar xzf /tmp/nvim-linux-x86_64.tar.gz -C /opt
    sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -f /tmp/nvim-linux-x86_64.tar.gz
  fi

  # Install lazygit
  if ! command -v lazygit &>/dev/null; then
    echo "==> Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo install /tmp/lazygit /usr/local/bin
    rm -f /tmp/lazygit /tmp/lazygit.tar.gz
  fi

  # Install git-delta
  if ! command -v delta &>/dev/null; then
    echo "==> Installing git-delta..."
    sudo apt install -y git-delta 2>/dev/null || echo "    git-delta not in apt, install manually: https://github.com/dandavison/delta/releases"
  fi

  # Install broot
  if ! command -v broot &>/dev/null; then
    echo "==> Installing broot..."
    curl -o /tmp/broot -fsSL https://dystroy.org/broot/download/x86_64-linux/broot
    sudo install /tmp/broot /usr/local/bin
    rm -f /tmp/broot
  fi

  # Install tmuxinator
  if ! command -v tmuxinator &>/dev/null; then
    echo "==> Installing tmuxinator..."
    sudo gem install tmuxinator
  fi

  # Install JetBrainsMono Nerd Font (GUI only)
  if [ "$HEADLESS" = false ]; then
    FONT_DIR="$HOME/.local/share/fonts"
    if [ ! -d "$FONT_DIR/JetBrainsMono" ]; then
      echo "==> Installing JetBrainsMono Nerd Font..."
      mkdir -p "$FONT_DIR/JetBrainsMono"
      curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
      unzip -o /tmp/JetBrainsMono.zip -d "$FONT_DIR/JetBrainsMono"
      rm -f /tmp/JetBrainsMono.zip
      fc-cache -fv
    fi
  fi

  echo "==> Stowing packages..."
  cd "$DOTFILES_DIR"
  if [ "$HEADLESS" = false ]; then
    stow "${BASE_PACKAGES[@]}" alacritty i3 tmuxinator
  else
    stow "${BASE_PACKAGES[@]}" tmuxinator
  fi
}

echo "dotfiles installer"
echo "=================="
if [ "$HEADLESS" = true ]; then
  echo "    Mode: server (headless) — GUI packages will be skipped"
fi

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *)      echo "Unsupported OS: $(uname -s)" && exit 1 ;;
esac

echo "==> Done!"
