-- In uv-workspace monorepos, each package has its own pyproject.toml but a
-- single shared .venv lives at the repo root. nvim-lspconfig would otherwise
-- root basedpyright at the nearest pyproject.toml (the package dir), where
-- there is no .venv, so every third-party import fails to resolve.
--
-- Root the python LSP at the dir that actually holds .venv; fall back to the
-- standard markers for ordinary single-package projects.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local lsp = vim.g.lazyvim_python_lsp or "basedpyright"
      opts.servers = opts.servers or {}
      opts.servers[lsp] = opts.servers[lsp] or {}
      -- basedpyright defaults to "recommended" (much stricter than pyright).
      -- Drop to "standard" to match pyright: no missing-type-stub warnings and
      -- none of basedpyright's extra reportUnknown* noise.
      opts.servers[lsp].settings = vim.tbl_deep_extend("force", opts.servers[lsp].settings or {}, {
        [lsp] = {
          analysis = {
            typeCheckingMode = "standard",
            -- Only analyze the files you actually have open. The default
            -- ("workspace") re-checks every file under the root, which in a big
            -- monorepo pins a core at ~100% every time you open a file.
            diagnosticMode = "openFilesOnly",
          },
        },
      })
      -- Resolve each buffer's root once and cache it. Two things matter here:
      --  * Caching keeps a given directory mapped to a STABLE root string, so
      --    the LSP framework reliably reuses one client per root instead of
      --    spawning a fresh pyright (full workspace analysis) per buffer -- the
      --    cause of one nvim running several pyright servers at once, each
      --    saturating a core.
      --  * Resolution stays synchronous (vim.fs.root is blocking); we only hand
      --    the already-resolved root to on_dir, so there's no async window in
      --    which concurrently-opened buffers race to create duplicate clients.
      local root_cache = {} ---@type table<string, string> dir -> resolved root
      opts.servers[lsp].root_dir = function(bufnr, on_dir)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        if fname == "" then
          return on_dir(vim.fn.getcwd())
        end
        local dir = vim.fs.dirname(fname)
        local cached = root_cache[dir]
        if cached then
          return on_dir(cached)
        end
        local root = vim.fs.root(fname, ".venv") -- uv workspace root (shared venv)
          or vim.fs.root(fname, {
            "pyproject.toml",
            "setup.py",
            "setup.cfg",
            "requirements.txt",
            "Pipfile",
            "pyrightconfig.json",
            ".git",
          })
          or dir
        root_cache[dir] = root
        on_dir(root)
      end
    end,
  },
}
