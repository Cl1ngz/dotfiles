vim.g.mapleader = " "

local keymap = vim.keymap

keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

keymap.set("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights (space+n+h)" })

-- increment/decrement numbers
keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" }) -- increment
keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" }) -- decrement

-- window management
keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" }) -- split window vertically
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" }) -- split window horizontally
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" }) -- make split windows equal width & height
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" }) -- close current split window

keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" }) -- open new tab
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" }) -- close current tab
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" }) --  go to next tab
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" }) --  go to previous tab
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" }) --  move current buffer to new tab

-- Line moving
keymap.set("n", "<A-Up>", ":m .-2<CR>==", { desc = "Move line up", silent = true })
keymap.set("n", "<A-Down>", ":m .+1<CR>==", { desc = "Move line down", silent = true })
keymap.set("i", "<A-Up>", "<Esc>:m .-2<CR>==gi", { desc = "Move line up in insert mode", silent = true })
keymap.set("i", "<A-Down>", "<Esc>:m .+1<CR>==gi", { desc = "Move line down in insert mode", silent = true })
keymap.set("v", "<A-Up>", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up", silent = true })
keymap.set("v", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down", silent = true })
