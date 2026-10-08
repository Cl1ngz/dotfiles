-- REPLACES -> lua/cl1ngz/plugins/colorscheme.lua
--
-- Both themes installed, toggle between them live, choice persists across
-- restarts.
--
--   <leader>ut     toggle rose-pine <-> everforest
--   :ThemeToggle   same thing
--   :Theme <name>  pick one directly (tab-completes)
--
-- The choice is written to stdpath("data")/theme.txt, so it is per-machine
-- and NOT in your dotfiles repo -- each laptop remembers its own.
--
-- Structure note: everforest is the "driver" spec and rose-pine is a
-- dependency of it. Lazy loads dependencies first, so both setup() calls are
-- guaranteed to have run before we apply one. Two sibling specs with equal
-- priority would race.

local DEFAULT = "everforest"
local state_file = vim.fn.stdpath("data") .. "/theme.txt"

local themes = {
  ["everforest"] = function()
    require("everforest").load()
  end,
  ["rose-pine"] = function()
    vim.cmd("colorscheme rose-pine")
  end,
}

local function read_choice()
  local f = io.open(state_file, "r")
  if not f then
    return DEFAULT
  end
  local name = vim.trim(f:read("*a") or "")
  f:close()
  return themes[name] and name or DEFAULT
end

local function write_choice(name)
  local f = io.open(state_file, "w")
  if f then
    f:write(name)
    f:close()
  end
end

local function apply(name, persist)
  if not themes[name] then
    vim.notify("Unknown theme: " .. tostring(name), vim.log.levels.WARN)
    return
  end

  themes[name]()

  -- lualine is theme = "auto"; re-running setup makes it re-resolve against
  -- the colorscheme we just applied.
  pcall(function()
    require("lualine").setup({ options = { theme = "auto" } })
  end)

  if persist then
    write_choice(name)
  end
end

return {
  {
    "neanias/everforest-nvim",
    name = "everforest",
    version = false,
    lazy = false,
    priority = 1000,

    dependencies = {
      { "rose-pine/neovim", name = "rose-pine" },
    },

    config = function()
      -- ---------------------------------------------------------------- --
      -- rose-pine
      -- ---------------------------------------------------------------- --
      require("rose-pine").setup({
        variant = "main", -- main | moon | dawn | auto
        dark_variant = "main",
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
          transparency = false,
        },

        highlight_groups = {
          DiagnosticUnderlineError = { undercurl = true },
          DiagnosticUnderlineWarn = { undercurl = true },
          DiagnosticUnderlineHint = { undercurl = true },
          DiagnosticUnderlineInfo = { undercurl = true },
        },
      })

      -- ---------------------------------------------------------------- --
      -- everforest
      -- ---------------------------------------------------------------- --
      require("everforest").setup({
        background = "hard", -- hard | medium | soft
        transparent_background_level = 0,
        ui_contrast = "high", -- low | high
        italics = true,
        disable_italic_comments = false,
        sign_column_background = "none",
        float_style = "bright", -- bright | dim
        dim_inactive_windows = false,

        diagnostic_text_highlight = false,
        diagnostic_virtual_text = "coloured",
        diagnostic_line_highlight = false,

        on_highlights = function(hl, _palette)
          hl.DiagnosticUnderlineError = { undercurl = true }
          hl.DiagnosticUnderlineWarn = { undercurl = true }
          hl.DiagnosticUnderlineHint = { undercurl = true }
          hl.DiagnosticUnderlineInfo = { undercurl = true }
        end,
      })

      -- ---------------------------------------------------------------- --
      -- apply + switching
      -- ---------------------------------------------------------------- --
      apply(read_choice(), false)

      vim.api.nvim_create_user_command("Theme", function(opts)
        apply(opts.args, true)
      end, {
        nargs = 1,
        desc = "Switch colorscheme",
        complete = function()
          return vim.tbl_keys(themes)
        end,
      })

      vim.api.nvim_create_user_command("ThemeToggle", function()
        local current = read_choice()
        apply(current == "everforest" and "rose-pine" or "everforest", true)
      end, { desc = "Toggle rose-pine <-> everforest" })

      vim.keymap.set("n", "<leader>ut", "<cmd>ThemeToggle<CR>", {
        desc = "Toggle theme (rose-pine / everforest)",
      })
    end,
  },
}
