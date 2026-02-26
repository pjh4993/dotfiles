-- Simple PDF browser preview using Python's built-in HTTP server
-- Works like markdown-preview: <leader>cp to toggle
local pdf_server = nil
local pdf_server_port = nil

local function pdf_preview_start()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" or vim.fn.filereadable(filepath) == 0 then
    vim.notify("No PDF file in current buffer", vim.log.levels.WARN)
    return
  end

  if pdf_server then
    vim.notify("PDF preview already running at http://localhost:" .. pdf_server_port, vim.log.levels.INFO)
    return
  end

  local dir = vim.fn.expand("%:p:h")
  local filename = vim.fn.expand("%:t")
  pdf_server_port = math.random(49152, 61000)

  pdf_server = vim.fn.jobstart({
    "python3", "-m", "http.server", tostring(pdf_server_port), "--directory", dir,
  }, {
    on_exit = function()
      pdf_server = nil
      pdf_server_port = nil
    end,
  })

  -- Give the server a moment to start, then open browser
  vim.defer_fn(function()
    local url = "http://localhost:" .. pdf_server_port .. "/" .. filename
    vim.fn.jobstart({ "open", url })
    vim.notify("PDF preview: " .. url, vim.log.levels.INFO)
  end, 300)
end

local function pdf_preview_stop()
  if not pdf_server then
    vim.notify("PDF preview is not running", vim.log.levels.INFO)
    return
  end
  vim.fn.jobstop(pdf_server)
  pdf_server = nil
  pdf_server_port = nil
  vim.notify("PDF preview stopped", vim.log.levels.INFO)
end

local function pdf_preview_toggle()
  if pdf_server then
    pdf_preview_stop()
  else
    pdf_preview_start()
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "pdf",
  callback = function()
    vim.keymap.set("n", "<leader>cp", pdf_preview_toggle, { buffer = true, desc = "PDF Preview" })
  end,
})

return {}
