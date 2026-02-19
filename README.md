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
| **octo.nvim** | GitHub PR/issue management | Both | Neovim plugin |
| **tmuxinator** | Tmux session manager | Both | Default layout included |
| **postgresql** | PostgreSQL 17 + pgvector | Both | `brew services start postgresql@17` |
| **bin** | Shell scripts (`gwt`, `lazygit` wrapper) | Both | Stowed to `~/.local/bin` |

## Quick Setup

```bash
git clone https://github.com/pjh4993/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The install script automatically detects your OS and:
- Installs dependencies via `brew` (macOS) or `apt` (Linux)
- Installs CLI tools: direnv, git-delta, broot, ripgrep, fd, jq, lazysql, carbonyl, infisical
- Installs PostgreSQL 17 + pgvector
- Installs Node.js via nvm (Linux) or brew (macOS)
- Installs tmuxinator with default session layout
- Stows the correct packages (skips aerospace on Linux, skips i3 on macOS)
- Safe to re-run — installs missing packages and restows configs

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

## gwt — Git Worktree Helper

`gwt` manages bare repo + worktree workflows for multi-agent parallel development. Each branch gets its own directory under the project root.

### Setup

```bash
gwt clone <url> [dir]    # Clone as bare repo with worktree layout
```

Layout:
```
project/
  .bare/                 # bare repo
  main/                  # worktree (main branch)
  feat/add-login/        # worktree (feat/add-login branch)
```

### Commands

| Command | Description |
|---------|-------------|
| `gwt clone <url> [dir]` | Clone as bare repo with worktree layout |
| `gwt add <branch> [base]` | Add worktree (creates branch if new) |
| `gwt rm <branch>` | Remove a worktree |
| `gwt ls` | List all worktrees |
| `gwt status [target]` | Show sync/merge/dirty status per worktree |
| `gwt sync` | Pull remote changes for all worktrees (ff-only) |
| `gwt rebase [target]` | Rebase current branch onto target (auto-stash) |
| `gwt clean [target]` | Remove worktrees merged into target + delete remote branches |
| `gwt rename <old> <new>` | Rename worktree branch and directory |
| `gwt lazygit` | Launch lazygit (auto-enters worktree if at bare root) |

Branch names with slashes (`feat/add-login`, `fix/auth-bug`) are fully supported — empty parent directories are cleaned up automatically.

### Example workflow

```bash
gwt clone git@github.com:user/project.git
cd project/main
gwt add feat/new-feature
cd ../feat/new-feature
# ... work on feature ...
gwt status              # check sync/merge status
gwt rebase              # rebase onto origin/main
gwt sync                # pull latest for all worktrees
gwt clean               # remove merged worktrees + remote branches
```
