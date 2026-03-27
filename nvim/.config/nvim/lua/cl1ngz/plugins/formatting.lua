return {
  "stevearc/conform.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("conform").setup({
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        svelte = { "prettier" },
        lua = { "stylua" },
        python = { "isort", "black" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        rust = { "rustfmt" },
        go = { "gofumpt", "goimports" }, -- Added for Go
        zig = { "zigfmt" }, -- Added for Zig
      },
      format_on_save = {
        lsp_fallback = true,
        async = false,
        timeout_ms = 1000,
      },
    })
  end,
}
