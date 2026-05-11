-- local hl = require("hyprland")

hl.config({
	decoration = {
		rounding = 25,

		active_opacity = 1.0,
		inactive_opacity = 0.92,

		blur = {
			enabled = true,
			size = 10,
			passes = 1,
			noise = 0.01,
			contrast = 0.6,
			vibrancy = 0.1,
		},

		shadow = {
			enabled = true,
			range = 25,
			render_power = 3,
			-- You can use rgba strings or hex values in the new Lua API
			color = "rgba(1a1b2699)",
		},
	},
})
