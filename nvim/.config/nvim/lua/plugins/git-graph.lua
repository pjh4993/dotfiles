return {
  -- Disable gitgraph.nvim in favor of vim-flog
  { "isakbm/gitgraph.nvim", enabled = false },

  {
    "rbong/vim-flog",
    dependencies = { "tpope/vim-fugitive" },
    cmd = { "Flog", "Flogsplit" },
    keys = {
      {
        "<leader>gl",
        function()
          -- bare repo root: git status fails, cd into a worktree first
          if vim.trim(vim.fn.system("git rev-parse --is-bare-repository 2>/dev/null")) == "true" then
            local wt = vim.trim(vim.fn.system(
              "git worktree list --porcelain | awk '/^worktree / && !/\\.bare$/ {print $2; exit}'"
            ))
            if wt ~= "" then
              vim.cmd("cd " .. vim.fn.fnameescape(wt))
            end
          end
          vim.cmd("Flog -all")
        end,
        desc = "Git Graph (Flog)",
      },
    },
  },
}
