#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_PACKAGES=(nvim alacritty tmux zsh git lazygit)

install_macos() {
  echo "==> Detected macOS"

  if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  echo "==> Installing dependencies..."
  brew install stow neovim tmux alacritty zsh git lazygit direnv git-delta broot
  brew install --cask nikitabobko/tap/aerospace

  echo "==> Stowing packages..."
  cd "$DOTFILES_DIR"
  stow "${SHARED_PACKAGES[@]}" aerospace
}

install_linux() {
  echo "==> Detected Linux (Ubuntu/Debian)"

  echo "==> Installing dependencies..."
  sudo apt update
  sudo apt install -y stow neovim tmux zsh git i3 i3status xclip direnv broot curl

  # Install alacritty if not present
  if ! command -v alacritty &>/dev/null; then
    echo "==> Installing Alacritty via snap..."
    sudo snap install alacritty --classic 2>/dev/null || echo "    Snap not available, install Alacritty manually"
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

  # Install JetBrainsMono Nerd Font
  FONT_DIR="$HOME/.local/share/fonts"
  if [ ! -d "$FONT_DIR/JetBrainsMono" ]; then
    echo "==> Installing JetBrainsMono Nerd Font..."
    mkdir -p "$FONT_DIR/JetBrainsMono"
    curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -o /tmp/JetBrainsMono.zip -d "$FONT_DIR/JetBrainsMono"
    rm -f /tmp/JetBrainsMono.zip
    fc-cache -fv
  fi

  echo "==> Stowing packages..."
  cd "$DOTFILES_DIR"
  stow "${SHARED_PACKAGES[@]}" i3
}

echo "dotfiles installer"
echo "=================="

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *)      echo "Unsupported OS: $(uname -s)" && exit 1 ;;
esac

echo "==> Done!"
