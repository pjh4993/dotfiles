-- Keymaps for the VSCode-style switchable left sidebar (see util/sidebar.lua).
--
-- A dedicated `<leader>v` ("view") prefix keeps the four panels grouped like
-- VSCode's activity bar without colliding with LazyVim's `<leader>s` (search)
-- namespace. `<leader>e` stays mapped to the explorer for muscle memory.
--
-- Re-pressing the active view's key hides the sidebar; `<leader>vv` toggles
-- whatever was last shown (VSCode Ctrl+B).
local function sb(view)
  return function()
    require("util.sidebar").open(view)
  end
end

return {
  "folke/snacks.nvim",
  keys = {
    { "<leader>e", sb("explorer"), desc = "Sidebar: Explorer" },
    { "<leader>ve", sb("explorer"), desc = "Sidebar: Explorer" },
    { "<leader>vg", sb("git"), desc = "Sidebar: Git status" },
    -- <leader>vo (Outline) lives in plugins/outline.lua so the key lazy-loads
    -- outline.nvim before the controller requires it.
    { "<leader>vs", sb("search"), desc = "Sidebar: Search (grep)" },
    {
      "<leader>vv",
      function()
        require("util.sidebar").toggle_visible()
      end,
      desc = "Sidebar: Toggle visibility",
    },
  },
}
