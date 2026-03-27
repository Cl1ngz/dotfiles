return {
  "kevinhwang91/nvim-ufo",
  dependencies = {
    "kevinhwang91/promise-async",
    "nvim-treesitter/nvim-treesitter",
  },
  event = "BufReadPost",
  keys = {
    {
      "zR",
      function()
        require("ufo").openAllFolds()
      end,
      desc = "Open all folds",
    },
    {
      "zM",
      function()
        require("ufo").closeAllFolds()
      end,
      desc = "Close all folds",
    },
    {
      "zr",
      function()
        require("ufo").openFoldsExceptKinds()
      end,
      desc = "Open folds except kinds",
    },
    {
      "zm",
      function()
        require("ufo").closeFoldsWith()
      end,
      desc = "Close folds with level",
    },
    {
      "zk",
      function()
        local winid = require("ufo").peekFoldedLinesUnderCursor()
        if not winid then
          vim.lsp.buf.hover()
        end
      end,
      desc = "Peek folded lines or hover",
    },
  },
  config = function()
    -- start with all folds open
    vim.o.foldlevel = 99
    vim.o.foldlevelstart = 99
    vim.o.foldenable = true
    vim.o.foldcolumn = "0"

    -- custom virtual-text handler to show suffix count
    local handler = function(virtText, lnum, endLnum, width, truncate)
      local newVirtText = {}
      local suffix = (" 󰁂 %d "):format(endLnum - lnum)
      local sufWidth = vim.fn.strdisplaywidth(suffix)
      local targetWidth = width - sufWidth
      local curWidth = 0
      for _, chunk in ipairs(virtText) do
        local chunkText = chunk[1]
        local chunkWidth = vim.fn.strdisplaywidth(chunkText)
        if curWidth + chunkWidth < targetWidth then
          table.insert(newVirtText, chunk)
          curWidth = curWidth + chunkWidth
        else
          chunkText = truncate(chunkText, targetWidth - curWidth)
          table.insert(newVirtText, { chunkText, chunk[2] })
          if curWidth + vim.fn.strdisplaywidth(chunkText) < targetWidth then
            suffix = suffix .. (" "):rep(targetWidth - curWidth - vim.fn.strdisplaywidth(chunkText))
          end
          break
        end
      end
      table.insert(newVirtText, { suffix, "MoreMsg" })
      return newVirtText
    end

    require("ufo").setup({
      provider_selector = function(_, _, _)
        return { "lsp", "indent" }
      end,
      fold_virt_text_handler = handler,
    })
  end,
}
