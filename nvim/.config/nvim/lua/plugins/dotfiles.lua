return {
  -- Show hidden + gitignored files in snacks.picker and explorer
  {
    "folke/snacks.nvim",
    opts = {
      lazygit = {
        -- Use old paging format (map) so snacks.nvim's YAML serializer can write it;
        -- lazygit's migration auto-converts it to the new pagers[] format
        config = {
          git = {
            paging = {
              colorArg = "always",
              pager = "bash -c 'delta --dark --paging=never --side-by-side --width=$(({{columnWidth}} * 2))'",
            },
          },
        },
        win = {
          width = 0,
          height = 0,
        },
      },
      picker = {
        sources = {
          files = {
            hidden = true,
            ignored = true,
          },
          grep = {
            hidden = true,
            ignored = true,
          },
          explorer = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
  -- YAML path navigation and statusline display
  {
    "cuducos/yaml.nvim",
    ft = { "yaml" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      vim.api.nvim_create_autocmd("BufWinEnter", {
        pattern = { "*.yaml", "*.yml" },
        callback = function()
          vim.defer_fn(function()
            if vim.bo.filetype == "yaml" then
              vim.opt_local.foldmethod = "indent"
              vim.opt_local.foldlevel = 1
            end
          end, 50)
        end,
      })
    end,
  },
}
