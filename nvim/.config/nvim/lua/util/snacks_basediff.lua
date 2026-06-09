-- "Base-diff mode" for the Snacks explorer: a toggle that prunes the file
-- tree to only the files changed vs each worktree's base branch (committed
-- `git diff <base>...HEAD` -- i.e. what a PR for that branch would contain).
--
-- In the bare-repo `gwt` layout the explorer is rooted at the project dir and
-- every worktree is a top-level folder, so pruning to changed-vs-base files
-- naturally groups the result per worktree:
--
--   groot/                 (explorer, base-diff mode ON)
--   ├ develop/
--   │ ├ src/api.ts
--   │ ╰ README.md
--   ╰ feature-x/
--     ╰ src/login.ts
--
-- Implementation: patch the explorer Tree's `filter` so that, while the mode
-- is active, a node is only shown if its path is in the changed set (files +
-- their ancestor dirs). `compute()` builds that set by running one diff per
-- worktree. Non-bare repos diff just their own root.
--
-- Limitation: the explorer is a filesystem tree, so files deleted on the
-- branch (present in base, absent in HEAD) can't be shown -- they don't exist
-- on disk. Added/modified files (the common PR case) show fine.

local M = {}

M.active = false ---@type boolean
M.paths = {} ---@type table<string, boolean> abs paths to show (changed files + ancestor dirs)

local base_cache = {} ---@type table<string, string|false> worktree root -> base ref (or false)

---@param w string worktree root
---@return string? base ref
local function detect_base(w)
  local cached = base_cache[w]
  if cached ~= nil then
    return cached or nil
  end
  for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    vim.fn.system({ "git", "-C", w, "rev-parse", "--verify", "--quiet", ref })
    if vim.v.shell_error == 0 then
      base_cache[w] = ref
      return ref
    end
  end
  base_cache[w] = false
  return nil
end

-- Explorer cwds to operate on (falls back to the editor cwd if none open).
---@return string[]
local function explorer_cwds()
  local cwds = {} ---@type string[]
  local ok, pickers = pcall(Snacks.picker.get, { source = "explorer" })
  if ok then
    for _, p in ipairs(pickers) do
      local got, cwd = pcall(function()
        return vim.fs.normalize(p:cwd())
      end)
      if got then
        cwds[#cwds + 1] = cwd
      end
    end
  end
  if #cwds == 0 then
    cwds[1] = vim.fs.normalize((vim.uv or vim.loop).cwd())
  end
  return cwds
end

local function refresh_explorers()
  local ok, pickers = pcall(Snacks.picker.get, { source = "explorer" })
  if not ok then
    return
  end
  for _, p in ipairs(pickers) do
    if not p.closed then
      pcall(function()
        p.list:set_target()
      end)
      pcall(function()
        p:find()
      end)
    end
  end
end

-- Rebuild M.paths from the committed diff-vs-base of every worktree under cwd
-- (or cwd itself for a normal repo), and open ancestor dirs so changed files
-- are revealed in the pruned tree.
---@param cwd string
function M.compute(cwd)
  cwd = vim.fs.normalize(cwd)
  local WT = require("util.snacks_worktree_git")
  local Tree = require("snacks.explorer.tree")
  local roots = WT.is_bare_root(cwd) and WT.worktrees_under(cwd) or { cwd }

  for _, w in ipairs(roots) do
    local base = detect_base(w)
    if base then
      local files = vim.fn.systemlist({ "git", "-C", w, "diff", base .. "...HEAD", "--name-only" })
      if vim.v.shell_error == 0 then
        for _, rel in ipairs(files) do
          if rel ~= "" then
            local abs = vim.fs.normalize(w .. "/" .. rel)
            M.paths[abs] = true
            -- mark every ancestor dir up to cwd so the path stays visible
            local dir = vim.fs.dirname(abs)
            while dir and #dir >= #cwd do
              M.paths[dir] = true
              if dir == cwd then
                break
              end
              dir = vim.fs.dirname(dir)
            end
            -- reveal: open ancestor dirs so the file shows in the tree
            pcall(function()
              Tree:open(abs)
            end)
          end
        end
      end
    end
  end
end

-- Patch the explorer Tree's filter so base-diff mode prunes to M.paths.
-- Idempotent; safe to call at startup.
function M.patch()
  local Tree = require("snacks.explorer.tree")
  if Tree._basediff_patched then
    return
  end
  Tree._basediff_patched = true

  local orig_filter = Tree.filter
  -- Set as an own field on the singleton instance, shadowing the class method.
  Tree.filter = function(self, filter)
    if not M.active then
      return orig_filter(self, filter)
    end
    -- Base-diff mode shows exactly the changed set (files + ancestor dirs),
    -- deliberately bypassing the hidden/ignored/exclude filters: a changed
    -- dotfile is still a change you want to see. Tracked diff entries are
    -- never gitignored, so nothing unwanted leaks through.
    local paths = M.paths
    return function(node)
      return paths[node.path] == true
    end
  end

  -- While active, recompute on focus so commits/rebases made outside nvim
  -- (and base-ref updates) are reflected.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = vim.api.nvim_create_augroup("snacks_basediff", { clear = true }),
    callback = function()
      if not M.active then
        return
      end
      base_cache = {}
      M.paths = {}
      for _, cwd in ipairs(explorer_cwds()) do
        M.compute(cwd)
      end
      refresh_explorers()
    end,
  })
end

function M.toggle()
  M.patch()
  M.active = not M.active
  if M.active then
    base_cache = {}
    M.paths = {}
    for _, cwd in ipairs(explorer_cwds()) do
      M.compute(cwd)
    end
  end
  refresh_explorers()
  vim.notify("explorer base-diff: " .. (M.active and "on (changed vs base)" or "off"), vim.log.levels.INFO)
end

return M
