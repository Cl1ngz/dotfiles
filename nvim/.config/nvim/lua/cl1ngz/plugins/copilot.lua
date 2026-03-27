return {
  "github/copilot.vim",
  config = function()
    -- Enable Copilot for all filetypes
    vim.g.copilot_filetypes = { ["*"] = true } -- Enable Copilot for all filetypes

    -- Optional: Disable default tab key mapping
    vim.g.copilot_no_tab_map = false
    vim.g.copilot_assume_mapped = true

    -- Keybinding to accept Copilot suggestions
    -- vim.api.nvim_set_keymap("i", "<C-j>", 'copilot#Accept("<CR>")', { expr = true, silent = true })
  end,
}
