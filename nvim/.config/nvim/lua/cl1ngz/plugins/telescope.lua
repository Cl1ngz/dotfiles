return {
  "nvim-telescope/telescope.nvim",
  -- Removed branch = "0.1.x" to get the latest 2026 fixes for Treesitter v1.0
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    "nvim-tree/nvim-web-devicons",
    "folke/todo-comments.nvim",
    { "folke/trouble.nvim", dependencies = { "nvim-tree/nvim-web-devicons" } },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
      defaults = {
        path_display = { "smart" },
        -- This part ensures the previewer handles the new Treesitter correctly
        preview = {
          treesitter = true,
          filesize_limit = 0.1, -- MB
        },
        mappings = {
          i = {
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-j>"] = actions.move_selection_next,
            ["<C-q>"] = actions.send_selected_to_qflist,
            ["<C-t>"] = function(prompt_bufnr)
              require("trouble.sources.telescope").open(prompt_bufnr)
            end,
          },
        },
      },
    })

    telescope.load_extension("fzf")
    telescope.load_extension("todo-comments")

    -- Keymaps
    local keymap = vim.keymap
    keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find files" })
    keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
    keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
    keymap.set("n", "<leader>fc", "<cmd>Telescope grep_string<cr>", { desc = "Find string under cursor" })
    keymap.set("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { desc = "Find todos" })
  end,
}
