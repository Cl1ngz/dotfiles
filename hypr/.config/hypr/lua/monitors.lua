-- Set this to true if you want to cap everything at 60Hz to save battery
local battery_save = false

---------------------
-- Laptop Monitor  --
---------------------
hl.monitor({
	output = "eDP-1",
	mode = battery_save and "1920x1080@60" or "1920x1080@144",
	position = "0x0",
	scale = 1,
})

---------------------
-- External Monitor --
---------------------
hl.monitor({
	output = "HDMI-A-1",
	mode = "1920x1080@60",
	position = "1920x0",
	scale = 1,
	-- transform = 1 -- Uncomment if you want to rotate the screen
})

---------------------
-- Fallback Rule   --
---------------------
-- This catches any monitor not explicitly defined above
hl.monitor({
	output = "", -- empty string acts as the default/fallback
	mode = "preferred",
	position = "auto",
	scale = 1,
	-- for presentation purpose
	-- mirror = "eDP-1",
})

--------------------------
-- Examples and other shit
-- Example: Secondary Display Port
-- hl.monitor({
--     output   = "DP-1",
--     mode     = "1920x1080@60",
--     position = "1920x0",
--     scale    = 1
-- })
