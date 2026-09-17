-- `gwt add` from inside Neovim.
--
-- `gwt` (~/.local/bin/gwt) lays a project out as a bare repo plus one working
-- tree per branch: <project>/.bare/ + <project>/<branch>/. On top of the plain
-- `git worktree add`, `gwt add <branch>` fetches, picks the right base (local
-- branch / origin branch / new branch off HEAD), writes the worktree's direnv
-- stub and rewrites the *.code-workspace file. Shell out to the script rather
-- than reimplement any of that here.
--
-- Creating a worktree deliberately leaves cwd alone: the new directory just
-- appears under the project root, which the Snacks explorer already shows
-- (see util/snacks_worktree_git.lua for how it gets git decorations there).

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "gwt" })
end

-- Directory to run `gwt` from: the current buffer's own directory when it is a
-- real file on disk, else Neovim's cwd. `gwt add` resolves the project root
-- itself, so anywhere inside the repo works.
local function repo_cwd()
  local buf = vim.api.nvim_buf_get_name(0)
  if buf ~= "" and vim.fn.filereadable(buf) == 1 then
    return vim.fs.dirname(buf)
  end
  return vim.fn.getcwd()
end

-- Nudge any open Snacks explorer so the new worktree shows up without a
-- manual refresh. Wrapped in pcall: the action goes through the picker's input
-- window, which is gone if the explorer was closed meanwhile.
local function refresh_explorer()
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    return
  end
  for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
    pcall(function()
      picker:action("explorer_update")
    end)
  end
end

---@param branch string
---@param cwd string
local function run_add(branch, cwd)
  -- Async: `gwt add` fetches origin first, which can block for seconds.
  vim.system({ "gwt", "add", branch }, { cwd = cwd, text = true }, function(out)
    vim.schedule(function()
      local output = vim.trim(out.stdout or "")
      if out.code ~= 0 then
        local err = vim.trim(out.stderr or "")
        notify(err ~= "" and err or output, vim.log.levels.ERROR)
        return
      end
      notify(output ~= "" and output or ("created " .. branch))
      refresh_explorer()
    end)
  end)
end

-- Prompt for a branch name and create its worktree.
function M.add()
  if vim.fn.executable("gwt") == 0 then
    notify("`gwt` not found in PATH", vim.log.levels.ERROR)
    return
  end

  local cwd = repo_cwd()
  -- `--git-common-dir` resolves from any worktree *and* from the bare project
  -- root, unlike `--show-toplevel`, which fails at the bare root.
  if vim.system({ "git", "-C", cwd, "rev-parse", "--git-common-dir" }):wait().code ~= 0 then
    notify("not inside a git repo: " .. cwd, vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "gwt add branch: " }, function(input)
    local branch = vim.trim(input or "")
    if branch == "" then
      return
    end
    notify("creating worktree " .. branch .. "...")
    run_add(branch, cwd)
  end)
end

return M
