# CLAUDE.md — Worktree Root

This is the **worktree root**, not the repo source. The actual codebase lives inside individual worktree directories. See the CLAUDE.md inside each worktree (e.g. `main/CLAUDE.md`) for project-level details.

## Repo Layout

This repo uses a **bare repository + git worktree** pattern for parallel multi-agent development:

```
<project>/                        # ← you are here (worktree root)
├── .bare/                        # bare git repo (shared object store)
├── .git                          # file: "gitdir: ./.bare"
├── .claude/                      # Claude Code settings (shared across worktrees)
├── .data/                        # local data directory (not in git, shared across worktrees)
├── .documents/                   # reference documents (not in git, shared across worktrees)
├── .envrc                        # direnv — shared env vars for all worktrees
├── main/                         # worktree: main branch
├── <feature-branch>/             # worktree: one per active branch
└── ...
```

- `.bare/` is the shared git object database. All worktrees reference it.
- `.data/` is a shared local data directory for any data storage (outputs, parquet files, databases, etc.). Not checked into git. All worktrees can read/write here.
- `.documents/` contains reference documents (API guides, specs, PDFs, etc.) shared across all worktrees. Not checked into git.
- `.envrc` is loaded by [direnv](https://direnv.net/) and exports shared environment variables. Typically includes paths to `.data/` and `.documents/`, API keys, and other shared config.
- Each top-level directory (other than `.bare/`, `.git`, `.claude/`, `.data/`, `.documents/`) is a **git worktree** checked out on its own branch.
- Worktree directory names match their branch name.

## `gwt` — Worktree Helper CLI

This repo was cloned with `gwt clone` and should be managed with `gwt`:

```bash
# Core
gwt add <branch> [base]        # Add worktree (creates branch from base if new, checks out if exists)
gwt rm <branch>                # Remove a worktree
gwt ls                         # List all worktrees

# Sync & status
gwt status|st [target]         # Show sync/merge status of worktrees (default: main)
gwt sync                       # Pull remote changes for all worktrees (ff-only)
gwt rebase [target]            # Rebase current branch onto target (default: main)

# Maintenance
gwt clean [target]             # Remove worktrees whose branches are merged into target (default: main)
gwt rename|mv <old> <new>      # Rename worktree branch and directory

# Other
gwt lazygit|lg                 # Launch lazygit (auto-enters worktree if at bare root)
gwt clone <url> [dir]          # Clone as bare repo with worktree layout (initial setup only)
```

## MANDATORY: Worktree-First Workflow (for code changes)

**BEFORE making any code changes (editing files, creating branches, running commands that modify state), you MUST create a worktree first.** This is a blocking prerequisite for all write operations.

### Exception: Read-only investigation

You **may** read files, explore the codebase, and run read-only commands (e.g. `grep`, `git log`, `pytest --collect-only`) directly on existing worktrees (including `main/`) **without** creating a new worktree. This applies to:
- Investigating bugs or errors
- Understanding code structure
- Reviewing existing code
- Running read-only diagnostic commands

### Step-by-step (for tasks that modify code):

1. **Create a worktree** — run `gwt add <branch-name> main` from this root.
2. **`cd` into the worktree** — e.g. `cd <project-root>/<branch-name>/`
3. **Install dependencies** — run the project's dependency install command (e.g. `uv sync`, `npm install`) inside the worktree.
4. **Then start working** — only now may you edit files or run commands that modify state.

### Branch Naming Convention

Branch names MUST follow this format:

```
<type>/[ghi-<issue>-]<scope>-<action>-<detail>
```

- **type** — category prefix (see table below)
- **ghi-\<issue\>** — GitHub issue number prefix. **Required** when the branch originates from an issue; omit otherwise.
- **scope** — which package or area is affected (e.g. `api`, `db`, `auth`, `cli`, `docs`)
- **action** — what you're doing (e.g. `add`, `fix`, `refactor`, `update`, `remove`, `migrate`)
- **detail** — specific subject (e.g. `user-auth-endpoint`, `retry-logic`, `partition-layout`)

| Type | When to use | Example |
|------|-------------|---------|
| `feat/` | New feature | `feat/api-add-user-auth-endpoint` |
| `fix/` | Bug fix (from issue) | `fix/ghi-42-db-handle-connection-timeout` |
| `refactor/` | Code restructuring | `refactor/db-migrate-partition-layout` |
| `chore/` | Maintenance, CI, deps | `chore/ghi-15-monorepo-upgrade-pytest-to-8` |
| `docs/` | Documentation only | `docs/api-add-usage-guide` |

Rules:
- Use lowercase, hyphens for spaces (`kebab-case`).
- **Always include `ghi-<issue>-`** when the work originates from a GitHub issue, placed right after the type prefix.
- **Always include the scope** so you can tell which package/area the branch affects at a glance.
- Be specific enough that the branch name alone tells you **what** is changing and **where**.
- Aim for 4–8 words after the type prefix (not counting hyphens).
- **BAD:** `dashboard`, `fix-bug`, `feat/user-auth`
- **GOOD:** `feat/api-add-user-auth-endpoint`, `fix/ghi-42-db-skip-empty-rows`, `refactor/db-split-read-write-modules`

### Merging PRs

When merging PRs with `gh pr merge`, **never use `--delete-branch`**. In a bare repo + worktree layout, `--delete-branch` tries to switch the local checkout to `main`, but `main` is already checked out in the `main/` worktree — causing a git error.

Instead:
1. **Merge without deleting the branch**: `gh pr merge <number> --squash`
2. **Clean up the worktree manually**: `gwt rm <branch-name>`
3. **Sync main**: `gwt sync`

### Other Rules

- **One agent per worktree** — never have two agents editing the same worktree simultaneously.
- **Do not work on `main`** — the `main` worktree is read-only reference. Always branch off it.
- **Commits are shared instantly** — all worktrees share `.bare/`, so commits in one worktree are visible to others via `git log`.
- **Clean up after merge** — `gwt rm <branch-name>` once the branch is merged.
- **Do not run project commands at this root** — dependency installs, tests, and application code must be run inside a worktree, not from this root.
