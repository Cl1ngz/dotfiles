-- local hl = require("hyprland")
local colors = require("lua.colors") -- Import Matugen colors

---------------------
--  Module Imports --
---------------------
require("lua.monitors")
require("lua.startup")
require("lua.windowrule")
require("lua.keybinds")
require("lua.animations")
require("lua.input_gestures")
require("lua.decorations")

---------------------
-- Main Config     --
---------------------
hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 3,
		border_size = 1,

		col = {
			active_border = { colors = { colors.primary, colors.tertiary }, angle = 45 },
			inactive_border = colors.surface_container,
		},

		layout = "dwindle",
	},

	dwindle = {
		preserve_split = true,
	},

	master = {
		new_on_top = true,
	},

	misc = {
		disable_hyprland_logo = true,
		force_default_wallpaper = 0,
	},
})

---------------------
--  Layer Rules    --
---------------------
hl.layer_rule({
	match = { class = "^(selection)" },
	no_anim = true,
})

-- Note: 'colors.conf' should be ported to a 'lua/colors.lua'
-- where you define variables like:
-- local primary = "rgba(33ccffee)"
-- and then export them to the other files.
