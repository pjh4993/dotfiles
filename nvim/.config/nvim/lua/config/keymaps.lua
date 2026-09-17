-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Create a git worktree with the `gwt` helper (see util/gwt.lua). Prompts for a
-- branch name; cwd stays put, the new worktree just appears under the project
-- root. <leader>gW is free in LazyVim's git group.
vim.keymap.set("n", "<leader>gW", function()
  require("util.gwt").add()
end, { desc = "Git Worktree Add (gwt)" })
