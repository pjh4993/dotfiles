return {
  {
    "kyytox/data-explorer.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    cmd = { "DataExplorer", "DataExplorerFile" },
    keys = {
      { "<leader>fd", "<cmd>DataExplorer<cr>", desc = "Data Explorer" },
    },
    init = function()
      vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "*.parquet",
        callback = function()
          vim.cmd("DataExplorerFile")
        end,
      })
    end,
    config = function()
      require("data-explorer").setup()
    end,
  },
}
