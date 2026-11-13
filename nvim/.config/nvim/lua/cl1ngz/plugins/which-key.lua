-- You already had which-key installed, but with `opts = {}` -- so pressing
-- <leader> gave you an unlabelled wall of single letters. The `spec` below
-- names every group, so the popup reads like a menu:
--
--     f  Find            g  Git             h  Git hunk
--     s  Split           t  Tab             w  Session
--     x  Diagnostics     u  UI toggles      e  Explorer
--
-- Pause after <leader> and the menu appears. Pause after <leader>f and it
-- narrows to the find commands. That is the whole discovery problem solved.
--
-- Also: <leader>? (set in core/keymaps.lua) lists every mapping active in
-- the current buffer, LSP ones included.

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
  end,
  opts = {
    -- "classic" | "modern" | "helix"
    -- helix puts the menu in a bottom panel; try it if you like that layout.
    preset = "modern",

    spec = {
      { "<leader>e", group = "Explorer" },
      { "<leader>f", group = "Find (Telescope)" },
      { "<leader>g", group = "Git" },
      { "<leader>h", group = "Git hunk" },
      { "<leader>s", group = "Split" },
      { "<leader>t", group = "Tab" },
      { "<leader>u", group = "UI toggles" },
      { "<leader>w", group = "Session" },
      { "<leader>x", group = "Diagnostics / Trouble" },
      { "<leader>n", group = "Swap next (treesitter)" },
      { "<leader>p", group = "Swap prev (treesitter)" },

      -- Tab number jumps are noise in the menu -- collapse them into one row.
      { "<leader>1", desc = "Go to tab 1-9", hidden = false },
      { "<leader>2", hidden = true },
      { "<leader>3", hidden = true },
      { "<leader>4", hidden = true },
      { "<leader>5", hidden = true },
      { "<leader>6", hidden = true },
      { "<leader>7", hidden = true },
      { "<leader>8", hidden = true },
      { "<leader>9", hidden = true },
    },
  },
}
