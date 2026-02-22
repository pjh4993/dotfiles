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
              pager = "delta --dark --paging=never --side-by-side --width={{columnWidth}}",
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
}
