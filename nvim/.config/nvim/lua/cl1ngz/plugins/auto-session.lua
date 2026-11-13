-- Updated for the AutoSession <subcommand> namespace. The old Session* /
-- Autosession commands now emit deprecation warnings, so legacy_cmds is
-- turned off and every keymap uses the new form.
--
-- Two kinds of session, both already supported by this plugin:
--
--   1. PER-DIRECTORY (automatic)
--      Open nvim in ~/projects/foo, work, quit -> session saved for that dir.
--      Come back later, <leader>wr -> restored.
--
--   2. NAMED (manual)
--      :AutoSession save frontend     -> saved as "frontend", ignores cwd
--      :AutoSession restore frontend
--      Use these for "the files I need when working on X" style sessions.
--
-- <leader>wf opens a picker over BOTH kinds. You have Telescope, so it uses
-- that automatically.
--
-- Not sure a subcommand exists? Type  :AutoSession <Tab>  and it completes.

return {
  "rmagatti/auto-session",
  lazy = false,
  config = function()
    local auto_session = require("auto-session")

    auto_session.setup({
      -- Master switch for auto create/save/restore.
      enabled = true,

      -- Save on exit: no. Restore on startup: no -- you pick explicitly.
      -- Flip auto_restore to true if you'd rather have the cwd session come
      -- back the moment you open nvim in a project directory.
      auto_save = false,
      auto_restore = false,

      -- Stop defining the deprecated Session* / Autosession commands.
      -- This is what was producing:
      --   "SessionSave" is deprecated. Use "AutoSession save" instead
      legacy_cmds = false,

      -- Don't create sessions in these.
      suppressed_dirs = { "~/", "~/Dev/", "~/Downloads", "~/Documents", "~/Desktop/" },

      -- Don't leave junk behind: if the only buffers open are empty/unnamed,
      -- skip saving.
      auto_delete_empty_sessions = true,

      session_lens = {
        -- nil = autodetect. You have Telescope, so it'll use Telescope.
        -- Force it with "telescope" | "snacks" | "fzf" | "select".
        picker = nil,
      },
    })

    local keymap = vim.keymap

    -- Browse every saved session (per-directory AND named) in a picker.
    -- This is the one you'll use most.
    keymap.set("n", "<leader>wf", "<cmd>AutoSession search<CR>", { desc = "Find/search sessions" })

    -- Restore the session for the current directory.
    keymap.set("n", "<leader>wr", "<cmd>AutoSession restore<CR>", { desc = "Restore session for cwd" })

    -- Save the current session under the cwd.
    keymap.set("n", "<leader>ws", "<cmd>AutoSession save<CR>", { desc = "Save session for cwd" })

    -- Save under a name you type. Uses vim.ui.input, which dressing.nvim
    -- already prettifies for you.
    keymap.set("n", "<leader>wn", function()
      vim.ui.input({ prompt = "Session name: " }, function(name)
        if name and name ~= "" then
          vim.cmd("AutoSession save " .. name)
        end
      end)
    end, { desc = "Save session under a name" })

    -- Pick a session to delete.
    keymap.set("n", "<leader>wd", "<cmd>AutoSession delete<CR>", { desc = "Delete a session" })

    -- Turn auto-saving on/off for this run -- handy when you're about to open
    -- a pile of scratch buffers you don't want remembered.
    keymap.set("n", "<leader>wa", "<cmd>AutoSession toggle<CR>", { desc = "Toggle session autosave" })
  end,
}
