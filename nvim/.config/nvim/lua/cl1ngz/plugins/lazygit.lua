--   <leader>l   = trigger linting   (linting.lua)
--   <leader>lg  = lazygit           (this file)
--
-- Because <leader>l is BOTH a complete mapping and the prefix of another,
-- vim can't act on it immediately -- it has to wait out 'timeoutlen' to see
-- if a `g` is coming. So every lint trigger was sitting on a dead pause, and
-- lazygit needed that same pause before it would fire.
--
-- Moving lazygit to <leader>gg (the near-universal convention for it) frees
-- <leader>l to fire instantly, and gives <leader>g a real Git group that
-- which-key can label.

return {
  "kdheepak/lazygit.nvim",
  cmd = {
    "LazyGit",
    "LazyGitConfig",
    "LazyGitCurrentFile",
    "LazyGitFilter",
    "LazyGitFilterCurrentFile",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>gg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
    { "<leader>gf", "<cmd>LazyGitCurrentFile<cr>", desc = "LazyGit (current file history)" },
  },
}
