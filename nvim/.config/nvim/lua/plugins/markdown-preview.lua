return {
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function() vim.fn["mkdp#util#install"]() end,
    keys = {
      { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Markdown Preview" },
    },
    init = function()
      -- Open the preview in a WaveTerm webview pane instead of the system browser.
      -- markdown-preview.nvim calls g:mkdp_browserfunc with the preview URL.
      local wave_block = nil

      function _G.MkdpWaveOpen(url)
        -- Outside WaveTerm, fall back to the default browser.
        if vim.env.WAVETERM ~= "1" then
          vim.fn.jobstart({ "open", url })
          return
        end

        local cmd = { "wsh", "web", "open" }
        -- Reuse the same pane on re-toggle instead of stacking new webviews.
        if wave_block then
          vim.list_extend(cmd, { "--replace", "block:" .. wave_block })
        end
        table.insert(cmd, url)

        vim.fn.jobstart(cmd, {
          stdout_buffered = true,
          on_stdout = function(_, data)
            for _, line in ipairs(data or {}) do
              local id = line:match("created block block:(%S+)")
              if id then wave_block = id end
            end
          end,
        })
      end

      -- mkdp invokes the browser func by name over RPC; use a Vimscript shim.
      vim.cmd([[
        function! MkdpWaveBrowser(url) abort
          call v:lua.MkdpWaveOpen(a:url)
        endfunction
      ]])
      vim.g.mkdp_browserfunc = "MkdpWaveBrowser"
    end,
  },
}
