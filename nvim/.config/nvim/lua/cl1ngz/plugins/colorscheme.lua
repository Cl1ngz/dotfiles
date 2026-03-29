return {
  "rose-pine/neovim",
  name = "rose-pine",
  priority = 1000,
  config = function()
    require("rose-pine").setup({
      variant = "main", -- options: "main", "moon", "dawn", or "auto"
      dark_variant = "main", -- variant if system is dark
      dim_inactive_windows = false,
      extend_background_behind_borders = true,

      enable = {
        terminal = true,
        legacy_highlights = true,
        migrations = true,
      },

      styles = {
        bold = true,
        italic = true,
        transparency = false, -- set to true if you want Hyprland transparency
      },

      highlight_groups = {
        -- Overrides to match your diagnostic preferences
        DiagnosticUnderlineError = { undercurl = true },
        DiagnosticUnderlineWarn = { undercurl = true },
        DiagnosticUnderlineHint = { undercurl = true },
        DiagnosticUnderlineInfo = { undercurl = true },
      },
    })

    vim.cmd("colorscheme rose-pine")
  end,
}
