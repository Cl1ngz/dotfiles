return {
  "mrcjkb/rustaceanvim",
  version = "^5",
  lazy = false,
  config = function()
    vim.g.rustaceanvim = {
      server = {
        on_attach = function(client, bufnr)
          local opts = { buffer = bufnr, silent = true }
          vim.keymap.set("n", "K", function()
            vim.cmd.RustLsp("hover")
          end, opts)
        end,
        default_settings = {
          ["rust-analyzer"] = {
            cargo = { allFeatures = true },
            checkOnSave = true,
            check = {
              command = "clippy",
            },
            procMacro = { enable = true },
          },
        },
      },
    }
  end,
}
