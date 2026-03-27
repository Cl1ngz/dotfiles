return {
  "nvim-tree/nvim-tree.lua",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    require("nvim-tree").setup({
      view = { width = 30 },
      renderer = {
        indent_markers = { enable = true },
      },
      actions = {
        open_file = { window_picker = { enable = false } },
      },
    })
    vim.keymap.set("n", "<leader>ee", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle explorer" })
  end,
}
