return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  lazy = false,
  priority = 500, -- after colorscheme (1000), before everything else
  config = function()
    local ts = require("nvim-treesitter")

    ts.setup({})

    local ensure = {
      "bash",
      "c",
      "cpp",
      "css",
      "diff",
      "dockerfile",
      "git_config",
      "gitcommit",
      "gitignore",
      "graphql",
      "html",
      "javascript",
      "jsdoc",
      "json",
      "jsonc",
      "lua",
      "luadoc",
      "markdown",
      "markdown_inline",
      "python",
      "qmljs", -- QML
      "query",
      "regex",
      "rust",
      "scss",
      "svelte",
      "toml",
      "tsx",
      "typescript",
      "vim",
      "vimdoc",
      "yaml",
      "zig",
    }

    local installed = ts.get_installed()
    local missing = vim.tbl_filter(function(lang)
      return not vim.tbl_contains(installed, lang)
    end, ensure)

    if #missing > 0 then
      ts.install(missing)
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("cl1ngz_treesitter", { clear = true }),
      callback = function(ev)
        local lang = vim.treesitter.language.get_lang(ev.match)
        if not lang then
          return
        end
        if not vim.tbl_contains(ts.get_installed(), lang) then
          return
        end

        -- highlighting
        pcall(vim.treesitter.start, ev.buf, lang)

        -- indentation
        vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
