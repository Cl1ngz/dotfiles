return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
    { "antosha417/nvim-lsp-file-operations", config = true },
    { "folke/lazydev.nvim", opts = {} },
  },
  config = function()
    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    local cmp_nvim_lsp = require("cmp_nvim_lsp")

    -- MODERN NEODIM DIAGNOSTIC CONFIG
    vim.diagnostic.config({
      -- NEW WAY: Define signs directly in the text table
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = " ",
          [vim.diagnostic.severity.WARN] = " ",
          [vim.diagnostic.severity.HINT] = "󰠠 ",
          [vim.diagnostic.severity.INFO] = " ",
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
        source = "always",
        header = "",
        prefix = "",
      },
    })

    -- KEYMAPS
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }
        local keymap = vim.keymap

        opts.desc = "Show LSP references"
        keymap.set("n", "gR", "<cmd>Telescope lsp_references<CR>", opts)
        opts.desc = "Go to declaration"
        keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        opts.desc = "Show LSP definitions"
        keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)
        opts.desc = "See code actions"
        keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        opts.desc = "Smart rename"
        keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        opts.desc = "Show documentation"
        keymap.set("n", "K", vim.lsp.buf.hover, opts)

        -- Diagnostic keymaps
        opts.desc = "Go to previous diagnostic"
        keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
        opts.desc = "Go to next diagnostic"
        keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
        opts.desc = "Show line diagnostics"
        keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

        if vim.lsp.inlay_hint then
          opts.desc = "Toggle Inlay Hints"
          keymap.set("n", "<leader>th", function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
          end, opts)
        end
      end,
    })

    local capabilities = cmp_nvim_lsp.default_capabilities()

    mason_lspconfig.setup({
      handlers = {
        function(server_name)
          lspconfig[server_name].setup({ capabilities = capabilities })
        end,
        ["rust_analyzer"] = function() end, -- Handled by rustaceanvim
        ["ts_ls"] = function()
          lspconfig["ts_ls"].setup({ capabilities = capabilities })
        end,
        ["lua_ls"] = function()
          lspconfig["lua_ls"].setup({
            capabilities = capabilities,
            settings = { Lua = { diagnostics = { globals = { "vim" } } } },
          })
        end,
      },
    })
  end,
}
