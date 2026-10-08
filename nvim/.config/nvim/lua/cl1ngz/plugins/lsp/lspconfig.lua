return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "mason-org/mason.nvim",
    "mason-org/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
    { "antosha417/nvim-lsp-file-operations", config = true },
    { "folke/lazydev.nvim", opts = {} },
  },
  config = function()
    local cmp_nvim_lsp = require("cmp_nvim_lsp")

    vim.diagnostic.config({
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = " ",
          [vim.diagnostic.severity.WARN] = " ",
          [vim.diagnostic.severity.HINT] = "󰠠 ",
          [vim.diagnostic.severity.INFO] = " ",
        },
      },
      virtual_text = {
        prefix = "●",
        spacing = 4,
      },
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = {
        focusable = false,
        style = "minimal",
        border = "rounded",
        source = true, -- was "always" (removed in 0.11+)
        header = "",
        prefix = "",
      },
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }
        local keymap = vim.keymap

        opts.desc = "Go to declaration"
        keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

        opts.desc = "Show LSP definitions"
        keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)

        opts.desc = "Show documentation"
        keymap.set("n", "K", vim.lsp.buf.hover, opts)

        opts.desc = "Go to previous diagnostic"
        keymap.set("n", "[d", function()
          vim.diagnostic.jump({ count = -1, float = true })
        end, opts)

        opts.desc = "Go to next diagnostic"
        keymap.set("n", "]d", function()
          vim.diagnostic.jump({ count = 1, float = true })
        end, opts)

        opts.desc = "Show line diagnostics"
        keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

        opts.desc = "Toggle Inlay Hints"
        keymap.set("n", "<leader>th", function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
        end, opts)
      end,
    })

    local capabilities = cmp_nvim_lsp.default_capabilities()

    -- Applies to every server, mason-installed or not.
    vim.lsp.config("*", { capabilities = capabilities })

    vim.lsp.config("lua_ls", {
      settings = {
        Lua = {
          diagnostics = { globals = { "vim" } },
        },
      },
    })

    local qmlls_bin = vim.fn.executable("qmlls6") == 1 and "qmlls6"
      or (vim.fn.executable("qmlls") == 1 and "qmlls" or "/usr/lib/qt6/bin/qmlls")

    vim.lsp.config("qmlls", {
      cmd = { qmlls_bin, "-E" },
      filetypes = { "qml", "qmljs" },
    })

    vim.lsp.enable("qmlls")
  end,
}
