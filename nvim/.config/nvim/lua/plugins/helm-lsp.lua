-- helm-ls panics (and the whole server dies) when it receives a
-- `textDocument/didOpen` for a buffer whose URI is not `file://`:
--
--   panic: only file URIs are supported, got fugitive
--     helm-ls/.../document.IsValuesYamlFile(...)
--     helm-ls/.../handler.(*ServerHandler).DidOpen(...)
--
-- The base-diff feature (util/snacks_basediff.lua) opens vim-fugitive buffers
-- to show each file's committed base version. Such a buffer is named
-- `fugitive://.../templates/foo.yaml`, which still matches the helm ftdetect
-- pattern (`.*/templates/.*%.yaml`), so it gets `filetype=helm`, helm_ls
-- attaches, sends didOpen with the fugitive URI -- and crashes. After that
-- every helm_ls feature (hover, goto, lint) is dead until you restart it.
--
-- Fix: gate attachment in root_dir (async form -- not calling on_dir means the
-- client never starts for that buffer). Only attach for real, on-disk files;
-- skip anything with a URI scheme other than a plain absolute path. helm_ls
-- never sees the fugitive buffer, so it never panics.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.helm_ls = opts.servers.helm_ls or {}
      opts.servers.helm_ls.root_dir = function(bufnr, on_dir)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        -- Empty name, or a non-`file` URI scheme (fugitive://, oil://, ...):
        -- not a real file helm-ls can stat. Don't attach -> no didOpen -> no
        -- panic. A plain absolute path ("/Users/...") has no "scheme://" and
        -- passes through.
        if fname == "" or (fname:match("^%a[%w+.%-]*://") and not fname:match("^file://")) then
          return
        end
        -- Root at the chart (the dir holding Chart.yaml) so helm-ls resolves
        -- values.yaml and templates correctly; fall back to the file's dir.
        local root = vim.fs.root(fname, "Chart.yaml") or vim.fs.dirname(fname)
        on_dir(root)
      end
    end,
  },
}
