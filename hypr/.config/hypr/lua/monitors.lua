-- Set this to true if you want to cap everything at 60Hz to save battery
local battery_save = false

---------------------
--  Per-machine    --
---------------------
-- Same config on both laptops; the internal panel differs, so look up
-- this machine by hostname and use its row.
local function hostname()
	local f = io.open("/etc/hostname", "r")
	if f then
		local h = f:read("*l")
		f:close()
		if h and h ~= "" then
			return h:lower()
		end
	end
	return (os.getenv("HOSTNAME") or ""):lower()
end

local machines = {
	archie = { panel = "1920x1080", hz = 144 },
	cachi = { panel = "1920x1200", hz = 165 },
}

local me = machines[hostname()]

local function panel_mode()
	-- Unknown machine (new install, third laptop): let the panel decide
	-- instead of forcing a mode it may not support.
	if not me then
		return "preferred"
	end
	return me.panel .. "@" .. (battery_save and 60 or me.hz)
end

---------------------
-- Laptop Monitor  --
---------------------
hl.monitor({
	output = "eDP-1",
	mode = panel_mode(),
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
	transform = 1, -- Uncomment if you want to rotate the screen
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
