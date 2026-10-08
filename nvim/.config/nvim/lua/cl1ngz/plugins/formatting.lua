return {
  "stevearc/conform.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("conform").setup({
      formatters = {
        qmlformat = {
          command = vim.fn.executable("qmlformat6") == 1 and "qmlformat6" or "qmlformat",
          args = { "-i", "$FILENAME" },
          stdin = false,
        },
      },

      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        svelte = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        lua = { "stylua" },
        python = { "isort", "black" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        rust = { "rustfmt" },
        qml = { "qmlformat" },
        zig = { "zigfmt" },
        -- go = { "gofumpt", "goimports" }, -- re-enable in mason.lua too
      },

      format_on_save = {
        lsp_format = "fallback", -- was lsp_fallback = true
        async = false,
        timeout_ms = 1000,
      },
    })

    vim.keymap.set({ "n", "v" }, "<leader>mp", function()
      require("conform").format({ async = true, lsp_format = "fallback" })
    end, { desc = "Format file or range" })
  end,
}
