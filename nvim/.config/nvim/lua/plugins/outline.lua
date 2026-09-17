-- Live document outline (outline.nvim) used as the Outline view of the
-- VSCode-style sidebar (see util/sidebar.lua). Unlike a Snacks symbols picker
-- it follows the cursor and updates as you edit, like VSCode's Outline.
--
-- The `<leader>vo` mapping is defined here (not in plugins/sidebar.lua) so that
-- pressing it lazy-loads outline.nvim before the sidebar controller calls
-- `require("outline")`.
return {
  "hedyhli/outline.nvim",
  keys = {
    {
      "<leader>vo",
      function()
        require("util.sidebar").open("outline")
      end,
      desc = "Sidebar: Outline (live)",
    },
  },
  opts = {
    outline_window = {
      position = "left", -- dock in the same left slot as the other views
      relative_width = false, -- width is absolute columns...
      width = 40, -- ...to match the Snacks `sidebar` layout (width 40)
      auto_close = false, -- stay open after jumping to a symbol
      focus_on_open = true, -- focus the outline so you can navigate immediately
    },
    outline_items = {
      show_symbol_details = true,
    },
  },
}
