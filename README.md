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
| **claude** | Claude Code (settings, hooks) | Both | |
| **opencode** | opencode | Both | Shares Claude Code's rules, skills, and commands — see below |

## Quick Setup

```bash
git clone https://github.com/pjh4993/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The install script automatically detects your OS and:
- Installs dependencies via `brew` (macOS) or `apt` (Linux)
- Installs CLI tools: direnv, git-delta, broot, ripgrep, fd, jq, lazysql, carbonyl, infisical
- Installs opencode and wires it up to Claude Code's config (see [opencode](#opencode))
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

## opencode

[opencode](https://opencode.ai) is installed by `install.sh` (Homebrew on macOS, the official
installer on Linux, symlinked into `~/.local/bin`). Config lives in the `opencode` stow package at
`~/.config/opencode/opencode.json`.

### Sharing config with Claude Code

Both agents read the same context — nothing has to be duplicated. opencode does most of this
natively ([docs](https://opencode.ai/docs/rules/)):

| What | Claude Code | opencode |
|------|-------------|----------|
| Project rules | `./CLAUDE.md` | `./AGENTS.md`, falls back to `./CLAUDE.md` |
| Global rules | `~/.claude/CLAUDE.md` | `~/.config/opencode/AGENTS.md`, falls back to `~/.claude/CLAUDE.md` |
| Skills | `.claude/skills/<name>/SKILL.md`, `~/.claude/skills/…` | reads both directly |
| Commands | `~/.claude/commands/*.md` | `~/.config/opencode/commands` → symlinked to `~/.claude/commands` by `install.sh` |

Notes:

- Rules **fall back**, they don't merge: a repo with both `AGENTS.md` and `CLAUDE.md` gets only
  `AGENTS.md`. Same for the global pair — so this repo deliberately ships **no**
  `~/.config/opencode/AGENTS.md`, which would shadow `~/.claude/CLAUDE.md`.
- `CLAUDE.local.md` isn't part of opencode's fallback chain, so it's listed under `instructions`
  in `opencode.json` (instructions are additive on top of the rules file).
- Bridged commands: opencode ignores Claude-only frontmatter (`allowed-tools`, `argument-hint`)
  and reads `description` + the body as the template. `$ARGUMENTS` and `$1`, `$2` work in both.
  A bare `model: sonnet` won't resolve though — opencode needs a provider prefix
  (`anthropic/claude-sonnet-4-5`), so drop `model:` from commands meant for both.
- Subagents are *not* bridged. Claude's `~/.claude/agents/*.md` and opencode's
  `~/.config/opencode/agents/*.md` use incompatible frontmatter (`tools` is a comma string vs. a
  map), so port those by hand if needed.
- MCP servers are not bridged either — Claude's `~/.claude/.mcp.json` and opencode's `mcp` config
  key have different schemas. Add servers with `opencode mcp` or in `opencode.json`.
- To turn the Claude Code compatibility off: `OPENCODE_DISABLE_CLAUDE_CODE=1` (or the narrower
  `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT` / `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`).

### Models and auth

Deliberately no `model` or `provider` in `opencode.json` — pick one with `/models` after logging
in. Credentials land in `~/.local/share/opencode/auth.json`, outside this repo.

Login methods opencode 1.18 actually offers, per provider:

| Provider | Methods |
|----------|---------|
| `openai` | `ChatGPT Pro/Plus (browser)`, `ChatGPT Pro/Plus (headless)`, API key |
| `github-copilot` | device-code flow |
| `anthropic` | **API key only** |
| `amazon-bedrock`, `google-vertex` | ambient cloud credentials |

Use the Codex seat:

```bash
opencode auth login -p openai -m "ChatGPT Pro/Plus (browser)"
# on a headless server:
opencode auth login -p openai -m "ChatGPT Pro/Plus (headless)"
```

Claude runs stay in Claude Code — a Claude Code seat can't drive opencode. Its `anthropic` provider
takes an API key (a separate Console product from a seat), and the plugins that bridge a Claude
Pro/Max subscription are
[explicitly prohibited by Anthropic](https://opencode.ai/docs/providers/#anthropic), unbundled from
opencode as of 1.3.0. A LiteLLM proxy doesn't change the math either — it's a router, so every
`model_list` entry still needs its own API key or cloud credentials.

If an org LiteLLM gateway does appear, both tools consume the same Anthropic-format
[`/v1/messages`](https://docs.litellm.ai/docs/anthropic_unified) endpoint:

```bash
# Claude Code
export ANTHROPIC_BASE_URL=https://litellm.internal
export ANTHROPIC_AUTH_TOKEN=sk-virtual-key
```

```json
// opencode.json
"provider": { "anthropic": { "options": { "baseURL": "https://litellm.internal", "apiKey": "{env:LITELLM_KEY}" } } }
```

### Upgrading

`autoupdate` is off so opencode doesn't fight the package manager:

```bash
brew upgrade opencode  # macOS
opencode upgrade       # Linux
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
| `gwt add <branch> [base]` | Add worktree (checks out local, tracks remote, or creates new branch) |
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
