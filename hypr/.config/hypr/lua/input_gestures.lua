-- local hl = require("hyprland")

---------------------
--   Input Setup   --
---------------------
hl.config({
	input = {
		kb_layout = "pl,us",
		kb_variant = "",
		kb_model = "",
		kb_options = "grp:win_space_toggle", -- Enabled this for your Super+Space toggle
		kb_rules = "",
		numlock_by_default = true,

		follow_mouse = 0,
		sensitivity = -0.5, -- -1.0 - 1.0, 0 means no modification.

		-- Mouse acceleration settings
		force_no_accel = false,

		touchpad = {
			natural_scroll = false,
		},
	},
})

---------------------
--    Gestures     --
---------------------
-- 3-finger horizontal swipe to switch workspaces
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- 3-finger pinch out to toggle fullscreen
hl.gesture({
	fingers = 3,
	direction = "pinchout",
	action = "fullscreen",
})
