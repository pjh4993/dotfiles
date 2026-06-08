return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- highlight for files changed vs the base branch
    vim.api.nvim_set_hl(0, "GitBaseChanged", { link = "WarningMsg", default = true })

    -- Wrap the explorer's file format: append a colored dot to files/folders
    -- whose path differs from the base branch (see util/gitbase.lua).
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}
    opts.picker.sources.explorer = opts.picker.sources.explorer or {}
    opts.picker.sources.explorer.format = function(item, picker)
      local ret = Snacks.picker.format.file(item, picker)
      local gb = require("util.gitbase")
      if gb.base and item.file and gb.paths[item.file] then
        ret[#ret + 1] = { "  ●", "GitBaseChanged" }
      end
      return ret
    end

    -- pick up commits/checkouts done outside nvim
    vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost" }, {
      group = vim.api.nvim_create_augroup("gitbase_refresh", { clear = true }),
      callback = function()
        require("util.gitbase").maybe_refresh()
      end,
    })

    return opts
  end,
  keys = {
    { "<leader>eb", function() require("util.gitbase").enable() end, desc = "Explorer: mark files changed vs base branch" },
    { "<leader>eB", function() require("util.gitbase").disable() end, desc = "Explorer: clear base diff marks" },
  },
}
