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
  brew install stow neovim tmux alacritty zsh git lazygit direnv git-delta broot ripgrep fd node jq lazysql carbonyl infisical postgresql pgvector gnu-sed just
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
  sudo apt install -y stow tmux zsh git direnv curl unzip ripgrep fd-find jq sed just
  # Symlink fdfind to fd (Ubuntu/Debian installs fd as fdfind)
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
  fi

  if [ "$HEADLESS" = false ]; then
    sudo apt install -y i3 i3status xclip
  fi

  # Install alacritty if not present (GUI only)
  if [ "$HEADLESS" = false ] && ! command -v alacritty &>/dev/null; then
    echo "==> Installing Alacritty via snap..."
    sudo snap install alacritty --classic 2>/dev/null || echo "    Snap not available, install Alacritty manually"
  fi

  # Install nvm and Node.js
  if ! command -v nvm &>/dev/null && [ ! -d "$HOME/.nvm" ]; then
    echo "==> Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    echo "==> Installing Node.js (latest LTS)..."
    nvm install --lts
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

  # Install lazysql
  if ! command -v lazysql &>/dev/null; then
    echo "==> Installing lazysql..."
    LAZYSQL_VERSION=$(curl -s "https://api.github.com/repos/jorgerojas26/lazysql/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo /tmp/lazysql.tar.gz "https://github.com/jorgerojas26/lazysql/releases/download/v${LAZYSQL_VERSION}/lazysql_Linux_x86_64.tar.gz"
    tar xf /tmp/lazysql.tar.gz -C /tmp lazysql
    sudo install /tmp/lazysql /usr/local/bin
    rm -f /tmp/lazysql /tmp/lazysql.tar.gz
  fi

  # Install carbonyl
  if ! command -v carbonyl &>/dev/null; then
    echo "==> Installing carbonyl..."
    sudo apt install -y libnss3 libatk-bridge2.0-0t64 libcups2t64 libgbm1 libasound2t64
    CARBONYL_VERSION=$(curl -s "https://api.github.com/repos/fathyb/carbonyl/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo /tmp/carbonyl.zip "https://github.com/fathyb/carbonyl/releases/download/v${CARBONYL_VERSION}/carbonyl.linux-amd64.zip"
    unzip -o /tmp/carbonyl.zip -d /tmp
    sudo mkdir -p /opt/carbonyl
    sudo cp /tmp/carbonyl-"${CARBONYL_VERSION}"/* /opt/carbonyl/
    sudo ln -sf /opt/carbonyl/carbonyl /usr/local/bin/carbonyl
    rm -rf /tmp/carbonyl.zip /tmp/carbonyl-"${CARBONYL_VERSION}"
  fi

  # Install infisical
  if ! command -v infisical &>/dev/null; then
    echo "==> Installing infisical..."
    curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash
    sudo apt-get install -y infisical
  fi

  # Install PostgreSQL
  if ! command -v psql &>/dev/null; then
    echo "==> Installing PostgreSQL..."
    sudo apt install -y postgresql postgresql-client postgresql-server-dev-all
  fi

  # Install pgvector
  if ! sudo -u postgres psql -c "SELECT 1 FROM pg_extension WHERE extname='vector'" 2>/dev/null | grep -q 1; then
    echo "==> Installing pgvector..."
    cd /tmp
    git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git
    cd pgvector
    make && sudo make install
    cd /tmp && rm -rf pgvector
    cd "$DOTFILES_DIR"
  fi

  # Install tmuxinator
  if ! command -v tmuxinator &>/dev/null; then
    echo "==> Installing tmuxinator..."
    sudo apt install -y ruby
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
