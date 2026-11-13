-- Tabs (your main request). You run bufferline in `mode = "tabs"`, so tabs
-- ARE your buffer bar -- switching them is the thing you do most, and it was
-- costing 3 keystrokes. Now:
--
--     <A-l> / <A-h>     next / previous tab        <- the big one
--     <leader>1 .. 9    jump straight to tab N
--
-- Alt-based, so it sits in the same family as your <A-Up>/<A-Down> line
-- moves, and doesn't collide with vim-tmux-navigator on <C-h/j/k/l>.
--
-- If you'd rather have <Tab>/<S-Tab>, swap the two lines marked TABNAV. Be
-- aware that in most terminals <Tab> and <C-i> are the same keycode, so that
-- costs you <C-i> (jumplist forward) unless your terminal speaks the kitty
-- keyboard protocol.
--
-- <leader>t is now tabs ONLY, with mnemonics that read properly:
--     tn = tab new      (used to be "next" -- confusing)
--     tc = tab close
--     to = tab only     (close all others)
--     tf = tab from current buffer
--
-- <leader>th (inlay hints) moved OUT of the tab namespace to <leader>uh,
-- joining <leader>ut (theme toggle) under a "UI toggles" group. That edit
-- is in lspconfig.lua.

vim.g.mapleader = " "

local keymap = vim.keymap

keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlights" })

-- increment/decrement numbers
keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" })
keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

-- ---------------------------------------------------------------------------
-- Splits
-- ---------------------------------------------------------------------------
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

-- TABNAV: fast switching. Swap for <Tab>/<S-Tab> if you prefer (see header).
keymap.set("n", "<A-l>", "<cmd>tabnext<CR>", { desc = "Next tab" })
keymap.set("n", "<A-h>", "<cmd>tabprevious<CR>", { desc = "Previous tab" })

-- Jump straight to a tab by number. `Ngt` is native vim, so this needs no
-- plugin support and works regardless of what bufferline is doing.
for i = 1, 9 do
  keymap.set("n", "<leader>" .. i, i .. "gt", { desc = "Go to tab " .. i })
end

keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
keymap.set("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
keymap.set("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" })
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Current buffer in new tab" })

-- ---------------------------------------------------------------------------
-- Line moving
-- ---------------------------------------------------------------------------
keymap.set("n", "<A-Up>", ":m .-2<CR>==", { desc = "Move line up", silent = true })
keymap.set("n", "<A-Down>", ":m .+1<CR>==", { desc = "Move line down", silent = true })
keymap.set("i", "<A-Up>", "<Esc>:m .-2<CR>==gi", { desc = "Move line up", silent = true })
keymap.set("i", "<A-Down>", "<Esc>:m .+1<CR>==gi", { desc = "Move line down", silent = true })
keymap.set("v", "<A-Up>", ":m '<-2<CR>gv=gv", { desc = "Move selection up", silent = true })
keymap.set("v", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selection down", silent = true })

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------
-- Forgot what's available in this buffer? This lists every active mapping,
-- including the ones LSP and plugins attached.
keymap.set("n", "<leader>?", function()
  require("which-key").show({ global = false })
end, { desc = "Buffer keymaps (which-key)" })
