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

-- Fold every comment/review/reply in an octo PR buffer so they are collapsed
-- by default.  octo.nvim renders each comment header as virtual text with the
-- OctoTimelineItemHeading highlight group on that header line — we scan all
-- extmarks to collect those line numbers, then build one manual fold per
-- comment spanning from its header down to the line before the next header.
--
-- Navigation hints (standard Neovim fold keys):
--   za  — toggle the comment under the cursor
--   zR  — expand all (read everything)
--   zM  — collapse all (back to PR-body-only view)
local function setup_octo_comment_folds(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf].comment_folds_created then return end

  -- Collect every row that carries an OctoTimelineItemHeading virtual-text chunk.
  local header_rows = {}
  for _, ns_id in pairs(vim.api.nvim_get_namespaces()) do
    local ok, marks = pcall(
      vim.api.nvim_buf_get_extmarks, buf, ns_id, 0, -1, { details = true }
    )
    if ok then
      for _, mark in ipairs(marks) do
        local row, details = mark[2], mark[4]
        if details then
          for _, chunk in ipairs(details.virt_text or {}) do
            if (chunk[2] or ""):find("OctoTimelineItemHeading", 1, true) then
              header_rows[row] = true
              break
            end
          end
        end
      end
    end
  end

  local starts = vim.tbl_keys(header_rows)
  if #starts == 0 then return end   -- content not loaded yet; on_lines will retry
  table.sort(starts)

  local nlines = vim.api.nvim_buf_line_count(buf)

  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.foldminlines = 0
    pcall(vim.cmd, "normal! zE")   -- clear any pre-existing folds

    for i, row in ipairs(starts) do
      local last = (i < #starts) and (starts[i + 1] - 1) or (nlines - 1)
      if last >= row then
        -- fold command is 1-indexed
        pcall(vim.cmd, string.format("%d,%dfold", row + 1, last + 1))
      end
    end

    vim.opt_local.foldlevel = 0   -- start with all comments collapsed
  end)

  vim.b[buf].comment_folds_created = true
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("dotfiles_octo_fold", { clear = true }),
  pattern = "octo",
  callback = function(ev)
    local buf = ev.buf
    -- octo loads content asynchronously; debounce fold setup until
    -- 400 ms after the last buffer write to ensure extmarks are in place.
    local pending = false
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, b)
        if vim.b[b] and vim.b[b].comment_folds_created then
          return true  -- detach; nothing more to do
        end
        if pending then return end
        pending = true
        vim.defer_fn(function()
          pending = false
          setup_octo_comment_folds(b)
        end, 400)
      end,
    })
  end,
})

-- Auto-reload files changed outside nvim (e.g. by Claude Code, git)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = vim.api.nvim_create_augroup("dotfiles_autoreload", { clear = true }),
  command = "checktime",
})
