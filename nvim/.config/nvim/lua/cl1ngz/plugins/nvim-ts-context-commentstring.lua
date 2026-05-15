-- return {
--   "numToStr/Comment.nvim",
--   event = { "BufReadPre", "BufNewFile" },
--   dependencies = {
--     {
--       "JoosepAlviste/nvim-ts-context-commentstring",
--       -- This line is the critical fix for the language_tree crash
--       opts = { enable_autocmd = false },
--     },
--   },
--   config = function()
--     require("Comment").setup({
--       pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
--     })
--   end,
-- }
return {
  "JoosepAlviste/nvim-ts-context-commentstring",
  opts = {
    enable_autocmd = false,
  },
  config = function(_, opts)
    require("ts_context_commentstring").setup(opts)
    -- This tells Neovim's native commenting to ask this plugin for the right string
    local get_option = vim.filetype.get_option
    vim.filetype.get_option = function(filetype, option)
      return option == "commentstring" and require("ts_context_commentstring.internal").calculate_commentstring()
        or get_option(filetype, option)
    end
  end,
}
