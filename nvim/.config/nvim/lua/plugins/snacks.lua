return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- VSCode-style git decorations in the file explorer.
    --
    -- Snacks already does the structural work for us out of the box:
    --   * the explorer runs `git status --porcelain=v1` (working-tree status,
    --     same scope VSCode shows by default),
    --   * each entry gets a right-aligned letter badge (M / A / D / ? / R / !),
    --   * `formatters.file.git_status_hl` (on by default) tints the *filename*
    --     with the matching status highlight, and
    --   * status bubbles up so parent folders of a change are tinted too.
    --
    -- The only gap vs VSCode is colour: Snacks' defaults leave untracked files
    -- grey and modified files on DiagnosticWarn. Re-link the status groups to
    -- the theme's GitSigns colours so the explorer matches VSCode semantics
    -- (untracked/added = green, modified = change colour, deleted = red) while
    -- still adapting to whatever colorscheme is active.
    local function set_git_hls()
      local link = function(from, to)
        vim.api.nvim_set_hl(0, from, { link = to, default = false })
      end
      link("SnacksPickerGitStatusUntracked", "GitSignsAdd") -- ? -> green, like VSCode
      link("SnacksPickerGitStatusAdded", "GitSignsAdd") -- A -> green
      link("SnacksPickerGitStatusStaged", "GitSignsAdd") -- staged -> green
      link("SnacksPickerGitStatusModified", "GitSignsChange") -- M -> change colour
      link("SnacksPickerGitStatusRenamed", "GitSignsChange") -- R -> change colour
      link("SnacksPickerGitStatusCopied", "GitSignsChange") -- C -> change colour
      link("SnacksPickerGitStatusDeleted", "GitSignsDelete") -- D -> red
      link("SnacksPickerGitStatusUnmerged", "DiagnosticError") -- conflicts -> red
      -- Ignored intentionally left on its grey default.
      -- (SnacksBaseDiffName -- the changed-vs-base-PR tint -- is defined in
      -- util/snacks_basediff.lua, which blends a green bg from GitSignsAdd.)
    end

    set_git_hls()
    -- Re-apply after a colorscheme swap so the links survive `:colorscheme`.
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("snacks_git_hls", { clear = true }),
      callback = set_git_hls,
    })

    -- Show git status in the explorer even when it is rooted at a bare-repo
    -- worktree container (the `gwt` layout). See util/snacks_worktree_git.lua.
    require("util.snacks_worktree_git").patch()

    -- Always-on left-margin marks for files changed vs each branch's base PR.
    require("util.snacks_basediff").patch()

    return opts
  end,
}
