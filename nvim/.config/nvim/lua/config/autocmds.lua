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

-- Folding for octo.nvim PR/issue buffers (collapses CodeRabbit bot sections)
-- Level 1: _start/_end section markers + auto-generated comment wrappers
-- Level 2: <details> blocks nested inside sections
_G.octo_foldexpr = function()
  local line = vim.fn.getline(vim.v.lnum)
  -- CodeRabbit _start markers: <!-- walkthrough_start -->, <!-- tips_start -->, etc.
  if line:match("<!%-%-.+_start%s*%-%->") then
    return ">1"
  -- CodeRabbit _end markers: <!-- walkthrough_end -->, <!-- tips_end -->, etc.
  elseif line:match("<!%-%-.+_end%s*%-%->") then
    return "<1"
  -- Top-level auto-generated comment wrappers
  elseif line:match("^<!%-%-%s*This is an auto%-generated") then
    return ">1"
  elseif line:match("^<!%-%-%s*end of auto%-generated") then
    return "<1"
  -- <details> blocks (nested inside sections)
  elseif line:match("^<details") then
    return ">2"
  elseif line:match("^</details>") then
    return "<2"
  end
  return "="
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("dotfiles_octo_fold", { clear = true }),
  pattern = "octo",
  callback = function()
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.octo_foldexpr()"
    vim.opt_local.foldlevel = 0  -- start with all bot sections collapsed
    vim.opt_local.foldminlines = 2
  end,
})

-- Auto-reload files changed outside nvim (e.g. by Claude Code, git)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = vim.api.nvim_create_augroup("dotfiles_autoreload", { clear = true }),
  command = "checktime",
})
