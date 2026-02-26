-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Equalize splits when tmux pane or window is resized
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("dotfiles_resize", { clear = true }),
  command = "wincmd =",
})

-- Clear PDF buffer content (show hint instead of binary garbage)
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("dotfiles_pdf", { clear = true }),
  pattern = "*.pdf",
  callback = function()
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Press <leader>cp to open PDF in browser" })
    vim.bo.modifiable = false
    vim.bo.modified = false
  end,
})

-- Auto-reload files changed outside nvim (e.g. by Claude Code, git)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = vim.api.nvim_create_augroup("dotfiles_autoreload", { clear = true }),
  command = "checktime",
})
