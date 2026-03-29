return {
  "nvim-tree/nvim-tree.lua",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    require("nvim-tree").setup({
      -- 1. Disable git ignore filtering
      git = {
        enable = true,
        ignore = false, -- This ensures .gitignore files are SHOWN
        timeout = 400,
      },
      -- 2. Disable dotfile and custom filtering
      filters = {
        dotfiles = false, -- This ensures .hidden files are SHOWN
        custom = {}, -- Ensures no specific patterns are hidden
      },
      view = {
        width = 30,
      },
      renderer = {
        indent_markers = {
          enable = true,
        },
      },
      actions = {
        open_file = {
          window_picker = {
            enable = false,
          },
        },
      },
    })

    -- Keep your existing keymap
    vim.keymap.set("n", "<leader>ee", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle explorer" })
  end,
}
