-- Git status in the Snacks explorer for the bare-repo worktree layout.
--
-- The `gwt` helper lays projects out as a bare repo plus sibling worktrees:
--   <project>/.bare/          <- the bare git dir
--   <project>/.git            <- file: "gitdir: ./.bare"
--   <project>/<branch>/       <- one working tree per branch
--
-- Snacks' explorer decorates files by running a single `git status` at the
-- explorer root (`Snacks.git.get_root(cwd)`). When that root is the bare
-- project dir, `git status` fails ("fatal: this operation must be run in a
-- work tree"), so every file underneath renders with no git decoration --
-- including files that live inside the nested worktrees.
--
-- This module wraps `snacks.explorer.git.update`: when the explorer root is a
-- bare repo, it scans each nested worktree separately and merges the results
-- into Snacks' normal tree-decoration path. Non-bare repos fall through to the
-- original implementation unchanged.

local M = {}

local uv = vim.uv or vim.loop

-- cwd -> bool. Classifying a dir as bare needs a git call, so cache it; a
-- directory does not change between bare and non-bare during a session.
local is_bare_cache = {}

---@param cwd string
---@return boolean
local function is_bare_root(cwd)
  local cached = is_bare_cache[cwd]
  if cached ~= nil then
    return cached
  end
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--is-bare-repository" })
  local bare = vim.v.shell_error == 0 and out[1] == "true"
  is_bare_cache[cwd] = bare
  return bare
end

-- Absolute paths of the working trees nested under cwd (the bare dir itself
-- has no work tree, so it is skipped).
---@param cwd string
---@return string[]
local function worktrees_under(cwd)
  local out = vim.fn.systemlist({ "git", "-C", cwd, "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  local paths = {}
  for _, line in ipairs(out) do
    local p = line:match("^worktree (.+)$")
    if p then
      p = vim.fs.normalize(p)
      if p ~= cwd and p:find(cwd .. "/", 1, true) == 1 then
        paths[#paths + 1] = p
      end
    end
  end
  return paths
end

-- Scan every nested worktree, accumulate {status, abspath} entries, and hand
-- them to the explorer's `_update` once all scans finish. Mirrors the spawn /
-- parse logic in snacks.explorer.git.update, looped over the worktrees.
---@param Git table the snacks.explorer.git module
---@param cwd string
---@param opts table {untracked?: boolean, on_update?: fun()}
local function scan(Git, cwd, opts)
  local trees = worktrees_under(cwd)
  local results = {} ---@type table[]
  local pending = #trees

  local function finish()
    if Git._update(cwd, results) and opts.on_update then
      vim.schedule(opts.on_update)
    end
  end

  if pending == 0 then
    finish()
    return
  end

  local function done(output, wt)
    for _, line in ipairs(vim.split(output, "\0")) do
      if line ~= "" then
        local status, file = line:match("^(..) (.+)$")
        if status then
          results[#results + 1] = { status = status, file = wt .. "/" .. file }
        end
      end
    end
    pending = pending - 1
    if pending == 0 then
      finish()
    end
  end

  for _, wt in ipairs(trees) do
    local output = ""
    local stdout = assert(uv.new_pipe())
    local handle ---@type uv.uv_process_t?
    handle = uv.spawn("git", {
      stdio = { nil, stdout, nil },
      cwd = wt,
      hide = true,
      args = {
        "--no-pager",
        "--no-optional-locks",
        "status",
        "--porcelain=v1",
        "--ignored=matching",
        "-z",
        opts.untracked and "-unormal" or "-uno",
      },
    }, function()
      if handle then
        handle:close()
      end
    end)
    if not handle then
      stdout:close()
      done("", wt)
    else
      stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
          output = output .. data
        else
          stdout:close()
          done(output, wt)
        end
      end)
    end
  end
end

local CACHE_TTL = 15 * 60 -- match snacks.explorer.git

-- Wrap snacks.explorer.git.update so bare roots are handled by `scan`, while
-- everything else delegates to the stock implementation. Idempotent.
function M.patch()
  local Git = require("snacks.explorer.git")
  if Git._gwt_patched then
    return
  end
  Git._gwt_patched = true

  local orig_update = Git.update
  Git.update = function(cwd, opts)
    cwd = vim.fs.normalize(cwd)
    if not is_bare_root(cwd) then
      return orig_update(cwd, opts)
    end
    opts = opts or {}
    local ttl = opts.force and 0 or (opts.ttl or CACHE_TTL)
    -- State is keyed by root just like upstream; Snacks.git.get_root(cwd)
    -- returns cwd here, so is_dirty()/refresh() integrate unchanged.
    Git.state[cwd] = Git.state[cwd] or { tick = 0, last = 0 }
    local state = Git.state[cwd]
    if os.time() - state.last < ttl then
      return
    end
    state.last = os.time()
    scan(Git, cwd, opts)
  end

  -- Snacks watches the git index to refresh decorations, but a bare repo's
  -- per-worktree index lives under .bare/worktrees/*, which that watcher does
  -- not see. Nudge bare-root explorers to rescan on write/focus so edits show
  -- up. Scoped to bare roots, so normal repos keep their stock behaviour.
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
    group = vim.api.nvim_create_augroup("snacks_worktree_git", { clear = true }),
    callback = function()
      local pickers = Snacks.picker.get({ source = "explorer", tab = false })
      local nudged = false
      for _, p in ipairs(pickers) do
        local ok, cwd = pcall(function()
          return vim.fs.normalize(p:cwd())
        end)
        if ok and is_bare_root(cwd) and Git.state[cwd] then
          Git.state[cwd].last = 0
          nudged = true
        end
      end
      if nudged then
        pcall(function()
          require("snacks.explorer.watch").refresh()
        end)
      end
    end,
  })
end

return M
