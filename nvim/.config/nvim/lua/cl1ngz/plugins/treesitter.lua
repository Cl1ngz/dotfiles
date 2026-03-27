return {
  "nvim-treesitter/nvim-treesitter",
  event = { "BufReadPre", "BufNewFile" },
  build = ":TSUpdate",
  dependencies = { "windwp/nvim-ts-autotag" },
  config = function()
    -- In v1.0+, we setup directly via the main module
    require("nvim-treesitter").setup({
      highlight = { enable = true },
      indent = { enable = true },
      autotag = { enable = true },
      ensure_installed = {
        "rust",
        "zig",
        "go",
        "lua",
        "python",
        "c",
        "cpp",
        "bash",
        "typescript",
        "javascript",
        "tsx",
        "html",
        "css",
        "json",
        "yaml",
        "markdown",
        "markdown_inline",
        "vim",
        "vimdoc",
        "query",
      },
    })
  end,
}
