return {
  {
    "Mofiqul/dracula.nvim",
    opts = {},
    config = function()
      require("dracula").setup({
        overrides = {
          -- Default DiffAdd uses bright #50fa7b as background; tone it down
          DiffAdd = { bg = "#1e3a28" },
        },
      })
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dracula",
    },
  },
}
