local opt = vim.opt

opt.relativenumber = true
opt.number = true

-- Tabs & Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true

opt.wrap = true
opt.smoothscroll = true -- New in 0.10: smoother scrolling for wrapped lines
opt.cursorline = true
opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

-- Backspace & Clipboard
opt.backspace = "indent,eol,start"
opt.clipboard:append("unnamedplus")

-- Split windows
opt.splitright = true
opt.splitbelow = true

-- Search settings
opt.ignorecase = true
opt.smartcase = true

-- Decrease update time for better UI responsiveness
opt.updatetime = 250
opt.timeoutlen = 300

-- Better netrw (though you use nvim-tree)
vim.g.netrw_liststyle = 3
