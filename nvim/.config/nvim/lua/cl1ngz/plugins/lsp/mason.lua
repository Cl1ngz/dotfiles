-- REPLACES -> lua/cl1ngz/plugins/lsp/mason.lua
--
-- Changes from your version:
--   * org rename: williamboman -> mason-org
--   * mason-lspconfig now owns `automatic_enable` (v2 API). rust_analyzer is
--     excluded so it stops fighting rustaceanvim.
--
-- NOT handled here (install via pacman -- see packages.txt):
--   cppcheck            linting.lua wants it, not in the mason registry
--   luacheck            mason builds it via luarocks, which needs luarocks +
--                       a lua interpreter; Arch's `luacheck` package is simpler
--   qmlls / qmlformat   ship with Qt (qt6-declarative)
--   rust-analyzer       comes with rustup / the rust-analyzer package
--   zigfmt              ships inside the zig binary
--
-- If you later want to slim Mason down to just the npm/JS ecosystem (my
-- suggestion earlier), the candidates to move to pacman are: lua_ls,
-- clangd, clang-format, shellcheck, shfmt, black, isort, pylint.

return {
  "mason-org/mason.nvim",
  dependencies = {
    "mason-org/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    require("mason").setup({
      ui = {
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    })

    require("mason-lspconfig").setup({
      ensure_installed = {
        "ts_ls",
        "html",
        "cssls",
        "tailwindcss",
        "svelte",
        "lua_ls",
        "pyright",
        "bashls",
        "clangd",
        "graphql",
        "emmet_ls",
        "prismals",
        -- "gopls",
        "zls",
      },
      -- v2 replacement for the old `handlers` table. Installed servers get
      -- vim.lsp.enable()'d automatically; rust_analyzer is left to rustaceanvim.
      automatic_enable = {
        exclude = { "rust_analyzer" },
      },
    })

    require("mason-tool-installer").setup({
      ensure_installed = {
        "prettier",
        "eslint_d",
        "stylua",
        "isort",
        "black",
        "pylint",
        "shellcheck",
        "shfmt",
        "clang-format",
        -- "gofumpt",
        -- "goimports",
      },
    })
  end,
}
