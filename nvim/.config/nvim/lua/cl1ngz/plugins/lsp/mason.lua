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
