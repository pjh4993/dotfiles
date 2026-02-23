return {
  {
    "isakbm/gitgraph.nvim",
    dependencies = { "sindrets/diffview.nvim" },
    opts = {
      hooks = {
        on_select_commit = function(commit)
          vim.cmd(":DiffviewOpen " .. commit.hash .. "^!")
        end,
        on_select_range_commit = function(from, to)
          vim.cmd(":DiffviewOpen " .. from.hash .. "~1.." .. to.hash)
        end,
      },
    },
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
          require("gitgraph").draw({}, { all = true, max_count = 5000 })
        end,
        desc = "Git Graph",
      },
    },
  },
}
