-- "Base-diff marks" in the Snacks explorer: a left-margin sign on every file
-- (and its ancestor folders) that differs from its branch's base -- i.e. what
-- a PR for that branch would contain -- shown alongside the normal working-
-- tree git status, WITHOUT pruning the file list.
--
-- The base branch is resolved from the open PR for each worktree's branch via
-- `gh pr view` (so the marks mirror exactly what that PR shows). When there is
-- no connected PR (or gh is unavailable, or the PR's base ref can't be found)
-- the worktree is left unmarked -- the green changed-vs-base tint only ever
-- reflects a real PR's diff. (`:BaseDiff` still falls back to main|master so the
-- manual diff command keeps working on un-PR'd branches.)
--
-- In the bare-repo `gwt` layout the explorer is rooted at the project dir and
-- every worktree is a top-level folder, so the committed `git diff <base>...HEAD`
-- is run once per worktree and the marks naturally group per worktree:
--
--   groot/                 (explorer)
--   ├ develop/
--   │ ├▎src/api.ts          <- changed vs develop's base PR
--   │ ├ src/util.ts
--   │ ╰▎README.md
--   ╰ feature-x/
--     ╰▎src/login.ts
--
-- Implementation: two idempotent patches installed by M.patch():
--   * snacks.picker.format.file -- prepend a fixed-width sign chunk so changed
--     paths get a colored bar and everything else a blank (alignment is kept).
--   * snacks.explorer.git.update -- recompute the changed set whenever the
--     explorer refreshes its git decorations, so marks track commits/rebases.
--
-- Limitation: deletions can't be marked (the file is gone from disk, so there
-- is no tree node to decorate). Added/modified files (the common PR case) show.

local M = {}

M.paths = {} ---@type table<string, boolean> abs paths to mark (changed files + ancestor dirs)

local base_cache = {} ---@type table<string, string|false> worktree root -> base ref (or false)
local last_compute = 0 ---@type number os.time() of the last recompute
local TTL = 15 * 60 -- match snacks.explorer.git's cache window

local function norm(p)
  return vim.fs.normalize(p)
end

local bg_cache = {} ---@type table<string, string> base hl -> derived hl carrying our bg

-- Resolved background of `name` (following links), or nil if it has none.
---@param name string
---@return integer?
local function hl_bg(name)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and h.bg or nil
end

-- Resolved foreground of `name` (following links), or nil.
---@param name string
---@return integer?
local function hl_fg(name)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and h.fg or nil
end

-- Blend 24-bit colors `fg` over `bg` at `alpha` (0..1). Used to turn the
-- theme's (foreground-only) green into a subtle background tint.
---@param fg integer
---@param bg integer
---@param alpha number
---@return integer
local function blend(fg, bg, alpha)
  local function rgb(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
  end
  local fr, fgr, fb = rgb(fg)
  local br, bgr, bb = rgb(bg)
  local function mix(a, b)
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end
  return mix(fr, br) * 65536 + mix(fgr, bgr) * 256 + mix(fb, bb)
end

-- (Re)define SnacksBaseDiffName as a distinct green background -- the theme's
-- GitSignsAdd green blended into Normal's bg, so it reads clearly as "changed
-- vs base" and never collides with the (Visual-colored) cursor row. Called at
-- setup and on ColorScheme. Module-owned so the colour lives in one place.
local function define_hl()
  local green = hl_fg("GitSignsAdd") or hl_fg("DiffAdd") or 0x4CAF50
  local base = hl_bg("Normal")
  vim.api.nvim_set_hl(0, "SnacksBaseDiffName", { bg = base and blend(green, base, 0.30) or green })
end
M.define_hl = define_hl

-- Derive (and cache) a highlight that keeps `base`'s foreground but paints the
-- changed-vs-base background, so the filename keeps its git/file/dir tint while
-- gaining the highlight. Cleared on ColorScheme (see M.patch) so it re-resolves.
---@param base string? the filename chunk's original highlight group
---@return string derived highlight group name
local function with_bg(base)
  base = base or "SnacksPickerFile"
  local derived = bg_cache[base]
  if derived then
    return derived
  end
  derived = "SnacksBaseDiffName_" .. base
  local src = vim.api.nvim_get_hl(0, { name = base, link = false })
  -- SnacksBaseDiffName is the intended source, but some colorschemes give
  -- DiffChange (its default link) no bg -- fall back so the tint still shows.
  local bg = hl_bg("SnacksBaseDiffName") or hl_bg("Visual")
  vim.api.nvim_set_hl(0, derived, { fg = src.fg, bg = bg, bold = src.bold, italic = src.italic })
  bg_cache[base] = derived
  return derived
end

-- First verifiable ref wins, preferring the remote-tracking form.
---@param w string worktree root
---@param names string[] candidate branch names (e.g. {"develop", "main"})
---@return string? ref
local function first_ref(w, names)
  for _, name in ipairs(names) do
    for _, ref in ipairs({ "origin/" .. name, name }) do
      vim.fn.system({ "git", "-C", w, "rev-parse", "--verify", "--quiet", ref })
      if vim.v.shell_error == 0 then
        return ref
      end
    end
  end
  return nil
end

-- Resolve the PR base ref to diff against, asynchronously, and hand it to `cb`.
-- Looks up the open PR's base branch (via `gh pr view`, so the marks mirror
-- exactly what that PR would show) and verifies it as a ref; hands back nil when
-- there's no connected PR, gh is unavailable, or the base ref can't be found.
-- Callers that want a trunk fallback (only `:BaseDiff`) apply it themselves, so
-- the explorer marks stay PR-only. Cached: PR lookups hit the network -- doing
-- them inline is what made opening the explorer slow -- and a branch's base
-- rarely changes within a session.
---@param w string worktree root
---@param cb fun(base: string?)
local function resolve_base(w, cb)
  local cached = base_cache[w]
  if cached ~= nil then
    return cb(cached or nil)
  end
  -- Runs once the (async) PR lookup settles. Scheduled because first_ref()
  -- calls vim.fn.* which is unavailable in a libuv callback context.
  local function finish(pr)
    vim.schedule(function()
      local base = pr and first_ref(w, { pr }) or nil
      base_cache[w] = base or false
      cb(base)
    end)
  end
  if vim.fn.executable("gh") ~= 1 then
    return finish(nil)
  end
  -- The worktree dir may be gone (pruned/deleted while git metadata lingers, or
  -- a stale explorer cwd); vim.system() throws ENOENT if it can't chdir to cwd,
  -- so skip spawning for a missing dir and leave the worktree unmarked.
  local stat = (vim.uv or vim.loop).fs_stat(w)
  if not stat or stat.type ~= "directory" then
    return finish(nil)
  end
  vim.system(
    { "gh", "pr", "view", "--json", "baseRefName", "--jq", ".baseRefName" },
    { cwd = w, text = true },
    function(res)
      local name = res.code == 0 and vim.trim(res.stdout or "") or ""
      finish(name ~= "" and name or nil)
    end
  )
end

-- Explorer cwds currently open (falls back to the editor cwd if none).
---@return string[]
local function explorer_cwds()
  local cwds = {} ---@type string[]
  local ok, pickers = pcall(Snacks.picker.get, { source = "explorer" })
  if ok then
    for _, p in ipairs(pickers) do
      local got, cwd = pcall(function()
        return norm(p:cwd())
      end)
      if got then
        cwds[#cwds + 1] = cwd
      end
    end
  end
  if #cwds == 0 then
    cwds[1] = norm((vim.uv or vim.loop).cwd())
  end
  return cwds
end

-- Ask every open explorer to re-render with the current marks.
--
-- Deliberately debounced onto a timer rather than calling `picker:find()`
-- straight away. A find() aborts the picker's in-flight finder task, but a task
-- that was created and not yet stepped never sees that abort -- it is only
-- delivered at the finder's next `coroutine.yield()`, and the explorer's tree
-- walk doesn't yield until 100 items / 1ms -- so the "aborted" task later runs
-- to completion and appends a *second* full copy of the tree to the new item
-- list. The explorer then renders the whole tree twice, once after the other.
--
-- Our callers make that easy to hit: FocusGained refreshes twice in one tick,
-- and M.recompute() can complete synchronously (every base already cached)
-- while running *inside* the finder itself, via the patched Git.update -- which
-- would re-enter Finder:run and leave two live tasks filling one item list.
-- A timer moves the find to a later loop iteration and coalesces bursts.
local refresh_timer = assert((vim.uv or vim.loop).new_timer())
local refresh_tries = 0

local function refresh_explorers()
  refresh_timer:stop()
  refresh_timer:start(
    50,
    0,
    vim.schedule_wrap(function()
      local ok, pickers = pcall(Snacks.picker.get, { source = "explorer" })
      if not ok then
        return
      end
      -- A find already in flight would be aborted mid-run by ours, which is the
      -- same trap; wait it out instead. Bounded, so a slow finder can't starve
      -- the marks forever.
      for _, p in ipairs(pickers) do
        if not p.closed and p.finder and p.finder:running() and refresh_tries < 20 then
          refresh_tries = refresh_tries + 1
          return refresh_explorers()
        end
      end
      refresh_tries = 0
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
    end)
  )
end

local computing = false ---@type boolean a recompute is in flight

-- Add `abs` and its ancestor folders (up to `cwd`) to `paths` so a collapsed
-- directory containing a change still shows the bar.
local function mark(paths, cwd, abs)
  paths[abs] = true
  local dir = vim.fs.dirname(abs)
  while dir and #dir >= #cwd do
    paths[dir] = true
    if dir == cwd then
      break
    end
    dir = vim.fs.dirname(dir)
  end
end

-- Rebuild M.paths from the committed diff-vs-base of every worktree under each
-- open explorer (or the explorer cwd itself for a normal repo), then refresh.
--
-- Fully async: the `gh`/`git` work runs off the main loop, so opening the
-- explorer never blocks on it -- marks just appear a moment later. TTL-gated so
-- it piggybacks cheaply on git refreshes; pass force=true to bypass the cache.
---@param force? boolean
function M.recompute(force)
  if computing or (not force and (os.time() - last_compute) < TTL) then
    return
  end
  computing = true
  last_compute = os.time()

  local WT = require("util.snacks_worktree_git")
  local jobs = {} ---@type {cwd: string, w: string}[]
  for _, cwd in ipairs(explorer_cwds()) do
    cwd = norm(cwd)
    local roots = WT.is_bare_root(cwd) and WT.worktrees_under(cwd) or { cwd }
    for _, w in ipairs(roots) do
      jobs[#jobs + 1] = { cwd = cwd, w = w }
    end
  end

  local paths = {} ---@type table<string, boolean>
  local pending = #jobs
  if pending == 0 then
    computing = false
    return
  end

  local function done()
    pending = pending - 1
    if pending == 0 then
      M.paths = paths
      computing = false
      refresh_explorers()
    end
  end

  for _, job in ipairs(jobs) do
    resolve_base(job.w, function(base)
      if not base then
        return done()
      end
      -- --relative scopes paths to (and makes them relative to) `w`, so this is
      -- correct whether the explorer is rooted at the worktree root or a nested
      -- subdir of it.
      vim.system(
        { "git", "-C", job.w, "diff", "--relative", base .. "...HEAD", "--name-only" },
        { text = true },
        function(res)
          if res.code == 0 then
            for _, rel in ipairs(vim.split(res.stdout or "", "\n")) do
              if rel ~= "" then
                mark(paths, job.cwd, norm(job.w .. "/" .. rel))
              end
            end
          end
          vim.schedule(done)
        end
      )
    end)
  end
end

M.diff_mode = false ---@type boolean diff-on-open mode active (see toggle_diff_mode)
M.diff_state = nil ---@type {base_buf: integer, work_buf: integer}? buffers of the live base-diff
local diffing = false ---@type boolean re-entrancy guard while a diff is being opened

-- Tear down the live base-diff in the current tab. Closes the windows showing the
-- tracked working/base buffers (plus any stray fugitive scratch window), except
-- `keep`. We can't key off `&diff`: opening a new file into a diff window clears
-- it, so by replace time the stale windows no longer look like diffs -- the
-- tracked buffer numbers are what reliably identifies them. Force-close because
-- the working split often has unsaved edits; that only hides the buffer (its
-- contents survive), so no edits are lost.
---@param keep integer window id to never close
local function close_diff(keep)
  local st = M.diff_state
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= keep and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local tracked = st and (buf == st.base_buf or buf == st.work_buf)
      local scratch = vim.api.nvim_buf_get_name(buf):match("^fugitive://")
      if tracked or scratch then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  pcall(vim.cmd, "diffoff!") -- drop &diff on whatever window we kept
  M.diff_state = nil
end

-- Open a vertical diff of the current file against its branch's base -- the same
-- ref the explorer marks against: the connected PR's base branch, else
-- origin/main|master. Diffs against the merge-base (not base's tip) so it mirrors
-- the three-dot `base...HEAD` diff a PR shows -- i.e. only this branch's own
-- changes, not commits the base gained after this branch forked. The working
-- tree is on the right, so unstaged edits show too. :BaseDiff / <leader>gd
--
-- When `replace` is set, any existing base-diff in the tab is torn down first so
-- the new file's diff takes its place -- this is what diff mode uses as you move
-- between files (M.toggle_diff_mode).
---@param replace? boolean
function M.diff_current(replace)
  local target_win = vim.api.nvim_get_current_win()
  local target_buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(target_buf)
  if file == "" or vim.bo[target_buf].buftype ~= "" then
    return vim.notify("BaseDiff: not a file buffer", vim.log.levels.WARN)
  end
  local top = vim.trim(vim.fn.system({ "git", "-C", vim.fs.dirname(file), "rev-parse", "--show-toplevel" }) or "")
  if vim.v.shell_error ~= 0 or top == "" then
    return vim.notify("BaseDiff: not inside a git repo", vim.log.levels.WARN)
  end
  local w = norm(top)
  resolve_base(w, function(base)
    -- The explorer marks are PR-only, but the manual diff command still wants a
    -- sensible target on un-PR'd branches, so fall back to the trunk here.
    base = base or first_ref(w, { "main", "master" })
    if not base then
      return vim.notify("BaseDiff: no connected PR base or trunk found", vim.log.levels.WARN)
    end
    vim.system({ "git", "-C", w, "merge-base", base, "HEAD" }, { text = true }, function(res)
      local out = vim.trim(res.stdout or "")
      -- Fall back to base's tip if there's no common ancestor (unrelated history).
      local rev = (res.code == 0 and out ~= "") and out or base
      vim.schedule(function()
        -- The target window may be gone if focus moved during the async base
        -- lookup (first call hits `gh`); bail rather than diff the wrong place.
        if not vim.api.nvim_win_is_valid(target_win) then
          return
        end
        vim.api.nvim_set_current_win(target_win)
        -- Suppress the BufWinEnter handler for the windows Gvdiffsplit opens, so
        -- diff mode doesn't recurse on its own scratch/working buffers.
        diffing = true
        if replace then
          close_diff(target_win)
        end
        -- vim-fugitive is lazy (loads as a vim-flog dependency), so :Gvdiffsplit
        -- may not be registered yet -- pull it in on first use.
        if vim.fn.exists(":Gvdiffsplit") == 0 then
          pcall(function()
            require("lazy").load({ plugins = { "vim-fugitive" } })
          end)
        end
        local ok, err = pcall(vim.cmd, "Gvdiffsplit " .. rev)
        if ok then
          -- Mark the working buffer as carrying its own base-diff, so the diff-mode
          -- handler recognises an established diff and leaves it alone.
          pcall(function()
            vim.b[target_buf].basediff = true
          end)
          -- Record the two buffers now sharing the diff so a later replace can find
          -- and close their windows even after &diff has been cleared off them.
          local base_buf
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local b = vim.api.nvim_win_get_buf(win)
            if vim.wo[win].diff and vim.api.nvim_buf_get_name(b):match("^fugitive://") then
              base_buf = b
            end
          end
          M.diff_state = { base_buf = base_buf, work_buf = target_buf }
        else
          vim.notify("BaseDiff: " .. tostring(err), vim.log.levels.ERROR)
        end
        -- Clear the guard only after the induced BufWinEnter events have drained.
        vim.schedule(function()
          diffing = false
        end)
      end)
    end)
  end)
end

-- Toggle diff-on-open mode. While on, opening any file shows its base-diff and
-- swaps out the previous file's, so navigating the explorer walks you through
-- each file's diff. Turning it on diffs the current file immediately; turning it
-- off drops the base split and returns to the plain file. <leader>gD / :BaseDiffMode
function M.toggle_diff_mode()
  M.diff_mode = not M.diff_mode
  if M.diff_mode then
    vim.notify("BaseDiff mode: ON", vim.log.levels.INFO)
    if vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= "" then
      M.diff_current(true)
    end
  else
    -- Keep the working file visible; drop the base split. Prefer the tracked
    -- working window over wherever focus happens to be.
    local keep = vim.api.nvim_get_current_win()
    local st = M.diff_state
    if st then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == st.work_buf then
          keep = win
          break
        end
      end
    end
    close_diff(keep)
    vim.notify("BaseDiff mode: OFF", vim.log.levels.INFO)
  end
end

-- Install the format + git-refresh hooks. Idempotent; safe to call at startup.
function M.patch()
  define_hl()

  -- Paint the name of changed explorer entries with the changed-vs-base
  -- background. The explorer renders the filename as a single chunk tagged
  -- `field = "file"`; we swap its highlight for one that keeps the original
  -- foreground (git/file tint) and adds our bg. Untouched when not marked.
  local Format = require("snacks.picker.format")
  if not Format._basediff_patched then
    Format._basediff_patched = true
    local orig_file = Format.file
    Format.file = function(item, picker)
      local ret = orig_file(item, picker)
      local is_explorer = picker and picker.opts and picker.opts.source == "explorer"
      if is_explorer and item.file and M.paths[norm(item.file)] then
        for _, chunk in ipairs(ret) do
          if chunk.field == "file" then
            chunk[2] = with_bg(chunk[2])
          end
        end
      end
      return ret
    end
  end

  -- Recompute marks whenever the explorer refreshes its git decorations: the
  -- subsequent list re-render then renders them in the same pass.
  local Git = require("snacks.explorer.git")
  if not Git._basediff_patched then
    Git._basediff_patched = true
    local prev_update = Git.update
    Git.update = function(cwd, opts)
      local r = prev_update(cwd, opts)
      pcall(M.recompute, false)
      return r
    end
  end

  local group = vim.api.nvim_create_augroup("snacks_basediff", { clear = true })

  -- Recompute on focus so commits/rebases (and base-ref changes) made outside
  -- nvim are reflected even when no index-watch fires.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      M.recompute(true)
      refresh_explorers()
    end,
  })

  -- Derived bg highlights resolve a base group's fg/bg at creation time, so
  -- redefine the source and drop the cache on a colorscheme swap.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      bg_cache = {}
      define_hl()
    end,
  })

  -- Diff mode: while on, every file displayed is shown as a base-diff split,
  -- replacing the previous file's. See M.toggle_diff_mode. BufWinEnter fires
  -- whenever a buffer lands in a window (e.g. picked from the explorer).
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if not M.diff_mode or diffing then
        return
      end
      if vim.bo[ev.buf].buftype ~= "" then
        return -- only real file buffers (skips the picker, fugitive scratch, ...)
      end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name == "" or name:match("^fugitive://") then
        return
      end
      -- Already showing this buffer's own base-diff -> leave it. Only act on a
      -- file not yet diffed: a freshly opened one, or one dropped into a window
      -- that merely inherited &diff from the diff it displaced.
      if vim.wo.diff and vim.b[ev.buf].basediff then
        return
      end
      M.diff_current(true)
    end,
  })

  vim.api.nvim_create_user_command("BaseDiffDebug", M.debug, { desc = "snacks base-diff: diagnostics" })
  vim.api.nvim_create_user_command("BaseDiff", function()
    M.diff_current()
  end, { desc = "Vertical diff: current file vs branch base" })
  vim.api.nvim_create_user_command("BaseDiffMode", M.toggle_diff_mode, { desc = "Toggle base-diff-on-open mode" })
  vim.keymap.set("n", "<leader>gd", function()
    M.diff_current()
  end, { desc = "Diff file vs base branch" })
  vim.keymap.set("n", "<leader>gD", M.toggle_diff_mode, { desc = "Toggle base-diff mode" })
end

-- Print why marks may not be showing: patch state, explorer cwds, the resolved
-- base + changed-file count per worktree, and the current mark count. Uses
-- blocking git/gh on purpose so the output is immediate. :BaseDiffDebug
function M.debug()
  local Format = require("snacks.picker.format")
  local Git = require("snacks.explorer.git")
  local WT = require("util.snacks_worktree_git")
  local out = {
    "Format.file patched : " .. tostring(Format._basediff_patched == true),
    "Git.update patched  : " .. tostring(Git._basediff_patched == true),
    "gh on PATH          : " .. tostring(vim.fn.executable("gh") == 1),
    "current mark count  : " .. vim.tbl_count(M.paths),
    "SnacksBaseDiffName bg: " .. tostring(hl_bg("SnacksBaseDiffName")),
    "Visual bg (fallback) : " .. tostring(hl_bg("Visual")),
  }
  for _, cwd in ipairs(explorer_cwds()) do
    cwd = norm(cwd)
    local bare = WT.is_bare_root(cwd)
    out[#out + 1] = ("explorer cwd        : %s (bare=%s)"):format(cwd, tostring(bare))
    local roots = bare and WT.worktrees_under(cwd) or { cwd }
    for _, w in ipairs(roots) do
      base_cache[w] = nil -- force fresh resolution for the report
      resolve_base(w, function(base)
        local n = "?"
        if base then
          local files = vim.fn.systemlist({ "git", "-C", w, "diff", "--relative", base .. "...HEAD", "--name-only" })
          n = vim.v.shell_error == 0 and #files or ("err " .. vim.v.shell_error)
        end
        vim.schedule(function()
          vim.notify(("  worktree %s\n    base=%s changed=%s"):format(w, tostring(base), tostring(n)))
        end)
      end)
    end
  end
  vim.notify(table.concat(out, "\n"))
end

return M
