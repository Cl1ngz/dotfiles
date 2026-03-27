return {
  "williamboman/mason.nvim",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    require("mason").setup({
      ui = { icons = { package_installed = "✓", package_pending = "➜", package_uninstalled = "✗" } },
    })

    require("mason-lspconfig").setup({
      ensure_installed = {
        "ts_ls", -- Updated from tsserver
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
        "zls", -- Added Go and Zig
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
