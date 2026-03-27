return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      javascript = { "eslint_d" },
      typescript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescriptreact = { "eslint_d" },
      svelte = { "eslint_d" },
      python = { "pylint" }, -- Pylint is the one showing the import errors
      c = { "cppcheck" },
      cpp = { "cppcheck" },
      lua = { "luacheck" },
      sh = { "shellcheck" },
      bash = { "shellcheck" },
    }

    -- CUSTOM PYLINT CONFIGURATION
    local pylint = lint.linters.pylint
    pylint.args = {
      "--from-stdin",
      "stdin",
      "-f",
      "json",
      -- This hook finds your .venv and adds its site-packages to the path
      "--init-hook",
      [[
import sys, os
cwd = os.getcwd()
venv_base = os.path.join(cwd, ".venv", "lib")
if os.path.exists(venv_base):
    for d in os.listdir(venv_base):
        pkg_path = os.path.join(venv_base, d, "site-packages")
        if os.path.exists(pkg_path):
            sys.path.append(pkg_path)
      ]],
    }

    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function()
        lint.try_lint()
      end,
    })

    vim.keymap.set("n", "<leader>l", function()
      lint.try_lint()
    end, { desc = "Trigger linting for current file" })
  end,
}
