-- Tracks which files differ from a chosen git base ref (e.g. origin/main),
-- so the nvim-tree decorator can mark them. State only; rendering lives in
-- util/gitbase_decorator.lua.
local M = {}

M.base = nil ---@type string? current base ref; nil = feature disabled
M.paths = {} ---@type table<string, boolean> abs paths changed vs base (files + ancestor dirs)

local function repo_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end
  return out[1]
end

local function detect_base()
  for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref })
    if vim.v.shell_error == 0 then
      return ref
    end
  end
  return nil
end

-- Recompute the changed-vs-base set. Mirrors neo-tree: `git diff <base> HEAD`.
function M.refresh()
  M.paths = {}
  if not M.base then
    return
  end
  local root = repo_root()
  if not root then
    return
  end
  local files = vim.fn.systemlist({ "git", "-C", root, "diff", M.base, "HEAD", "--name-only" })
  if vim.v.shell_error ~= 0 then
    return
  end
  for _, rel in ipairs(files) do
    if rel ~= "" then
      local abs = root .. "/" .. rel
      M.paths[abs] = true
      -- bubble up so parent directories also get marked
      local dir = vim.fn.fnamemodify(abs, ":h")
      while dir and #dir >= #root do
        M.paths[dir] = true
        if dir == root then
          break
        end
        dir = vim.fn.fnamemodify(dir, ":h")
      end
    end
  end
end

local function reload_tree()
  -- repaint any open Snacks explorer (the default <leader>e)
  pcall(function()
    for _, p in ipairs(Snacks.picker.get({ source = "explorer" })) do
      p:refresh()
    end
  end)
  -- and neo-tree, if that's what's open
  pcall(function()
    require("neo-tree.sources.manager").refresh("filesystem")
  end)
end

function M.enable(base)
  M.base = base or detect_base()
  if not M.base then
    vim.notify("gitbase: no base branch found (origin/main, main, ...)", vim.log.levels.WARN)
    return
  end
  M.refresh()
  reload_tree()
  vim.notify("gitbase: marking files changed vs " .. M.base, vim.log.levels.INFO)
end

function M.disable()
  M.base = nil
  M.paths = {}
  reload_tree()
  vim.notify("gitbase: cleared", vim.log.levels.INFO)
end

-- Re-scan when the repo may have changed externally (commit/checkout/rebase).
function M.maybe_refresh()
  if M.base then
    M.refresh()
    reload_tree()
  end
end

return M
