return {
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
    },
    -- Re-apply patch after every install/update:
    -- Guards nvim_buf_call against buffers invalidated by snacks picker async callbacks.
    build = function()
      local path = vim.fn.stdpath("data") .. "/lazy/octo.nvim/lua/octo/init.lua"
      local lines = vim.fn.readfile(path)
      for i, line in ipairs(lines) do
        if line:match("^%s+vim%.api%.nvim_buf_call%(bufnr,") then
          if not (lines[i - 1] or ""):match("nvim_buf_is_valid") then
            table.insert(lines, i, "    if not vim.api.nvim_buf_is_valid(bufnr) then return end")
            vim.fn.writefile(lines, path)
            vim.notify("octo.nvim: applied nvim_buf_is_valid patch", vim.log.levels.INFO)
          end
          break
        end
      end
    end,
    opts = {
      picker = "snacks",
    },
    keys = {
      { "<leader>gp", "<cmd>Octo pr list<cr>", desc = "List PRs" },
      { "<leader>gi", "<cmd>Octo issue list<cr>", desc = "List Issues" },
    },
  },
}
