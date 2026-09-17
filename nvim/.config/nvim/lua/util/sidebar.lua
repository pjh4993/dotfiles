-- VSCode-style "activity bar" for the left sidebar.
--
-- VSCode docks a single sidebar on the left and lets you switch what it shows
-- -- Explorer, Source Control, Search, Outline -- one view at a time, and
-- clicking the active icon hides the sidebar. Neovim has no activity bar, so
-- this controller fakes one: each view knows how to open/close itself in the
-- left slot, and `M.open()` keeps exactly one of them there.
--
-- Most views are Snacks pickers pinned to the left `sidebar` layout (the
-- explorer is already one). The Outline view is `outline.nvim`, a live symbol
-- window that follows the cursor -- so a view is an abstract
-- {is_open, open, close} triple rather than always a picker.
--
-- Switching: `M.open(name)` hides the view if it is the active one (VSCode
-- "click the active icon"), otherwise closes whatever else is docked and opens
-- the requested view. `M.toggle_visible()` is the Ctrl+B show/hide.

local M = {}

-- Shared "behave like a docked sidebar panel" options for Snacks views,
-- mirroring the explorer source defaults (snacks `config/sources.lua`).
local function sidebar_opts(extra)
  return vim.tbl_deep_extend("force", {
    auto_close = false, -- don't close when focus leaves the panel
    jump = { close = false }, -- selecting a result keeps the panel open
    focus = "list",
    layout = { preset = "sidebar", preview = false },
  }, extra or {})
end

-- Build a view backed by a Snacks picker source. `is_open`/`close` find the
-- live picker by source on the current tab; `open` is supplied per source.
local function snacks_view(source, open)
  local function picker()
    for _, p in ipairs(Snacks.picker.get()) do -- current tab only
      if p.opts.source == source and not p.closed then
        return p
      end
    end
  end
  return {
    is_open = function()
      return picker() ~= nil
    end,
    close = function()
      local p = picker()
      if p then
        p:close()
      end
    end,
    open = open,
  }
end

-- The Outline view is outline.nvim. It may not be loaded yet (lazy-loaded on
-- its key), so guard every lookup -- "not loaded" simply means "not open".
local function outline_mod()
  local ok, m = pcall(require, "outline")
  return ok and m or nil
end

-- Logical view name -> { is_open, open, close }.
M.views = {
  explorer = snacks_view("explorer", function()
    -- The explorer source already defaults to the sidebar layout and stay-open
    -- options, so open it plainly to preserve all of its own config (git
    -- decorations, base-diff hooks, watchers, ...).
    Snacks.picker.explorer()
  end),
  git = snacks_view("git_status", function()
    Snacks.picker.git_status(sidebar_opts())
  end),
  search = snacks_view("grep", function()
    -- Focus the input so you can type the query immediately, like VSCode Search.
    Snacks.picker.grep(sidebar_opts({ focus = "input" }))
  end),
  outline = {
    is_open = function()
      local m = outline_mod()
      return m ~= nil and m.is_open()
    end,
    open = function()
      require("outline").open()
    end,
    close = function()
      local m = outline_mod()
      if m then
        m.close()
      end
    end,
  },
}

-- Last view that was explicitly opened, so the visibility toggle can restore it.
M.last = "explorer"

-- Switch the sidebar to `name`. Re-selecting the active view hides the sidebar;
-- any other docked view is replaced so only one occupies the left slot.
---@param name "explorer"|"git"|"outline"|"search"
function M.open(name)
  local view = M.views[name]
  if not view then
    return vim.notify("sidebar: unknown view " .. tostring(name), vim.log.levels.ERROR)
  end
  -- Active view re-pressed -> hide it (VSCode "click the active icon").
  if view.is_open() then
    return view.close()
  end
  -- Replace any other docked view.
  for other, v in pairs(M.views) do
    if other ~= name and v.is_open() then
      v.close()
    end
  end
  M.last = name
  view.open()
end

-- VSCode Ctrl+B: hide the sidebar if anything is docked, else reopen the last
-- view (defaulting to the explorer).
function M.toggle_visible()
  local open = {}
  for _, v in pairs(M.views) do
    if v.is_open() then
      open[#open + 1] = v
    end
  end
  if #open > 0 then
    for _, v in ipairs(open) do
      v.close()
    end
  else
    M.open(M.last or "explorer")
  end
end

return M
