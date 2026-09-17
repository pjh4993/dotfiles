-- Open .ipynb notebooks in euporie (a terminal Jupyter notebook UI) instead of
-- as raw JSON. Editing .ipynb opens euporie-notebook in a floating snacks
-- terminal and drops the (empty) notebook buffer; opening the same notebook
-- again brings back the running session.
--
-- Install: `uv tool install euporie --with ipykernel`. Its bundled "python3"
-- kernel runs in euporie's tool env, so for project packages register the
-- project venv once (`uv run python -m ipykernel install --user --name <proj>`)
-- and pick it in euporie (Kernel > Change Kernel).
-- Alacritty has no graphics protocol, so plots are drawn as text art.
--
-- `:IpynbRaw` opens the current/given notebook as plain JSON.
--
-- The BufReadCmd is registered here at spec-load time rather than in
-- config/autocmds.lua, which loads on VeryLazy -- too late for `nvim x.ipynb`.
local group = vim.api.nvim_create_augroup("dotfiles_ipynb", { clear = true })

local function read_raw(buf, file)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(file))
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = "json"
end

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "*.ipynb",
  callback = function(ev)
    local file = vim.fn.fnamemodify(ev.match, ":p")
    if ev.match:find("://") or vim.fn.executable("euporie-notebook") == 0 then
      if vim.fn.filereadable(file) == 1 then
        read_raw(ev.buf, file)
      end
      if not ev.match:find("://") then
        vim.notify("euporie-notebook not found: uv tool install euporie --with ipykernel", vim.log.levels.WARN)
      end
      return
    end
    vim.schedule(function()
      Snacks.bufdelete({ buf = ev.buf, force = true })
      Snacks.terminal({ "euporie-notebook", "--edit-mode", "vi", file }, {
        cwd = vim.fn.fnamemodify(file, ":h"),
        win = { position = "float", width = 0.95, height = 0.95, border = "rounded", title = " " .. vim.fn.fnamemodify(file, ":t") .. " " },
      })
    end)
  end,
})

vim.api.nvim_create_user_command("IpynbRaw", function(opts)
  local file = vim.fn.fnamemodify(opts.args ~= "" and opts.args or vim.fn.expand("%"), ":p")
  vim.cmd("noautocmd edit " .. vim.fn.fnameescape(file))
  read_raw(0, file)
end, { nargs = "?", complete = "file", desc = "Open a notebook as raw JSON" })

return {}
