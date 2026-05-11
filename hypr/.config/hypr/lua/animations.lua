-- Enable animations globally
hl.config({
	animations = { enabled = true },
})

---------------------
--  Bezier Curves  --
---------------------
-- Syntax: hl.curve("NAME", { type = "bezier", points = { {x0, y0}, {x1, y1} } })
hl.curve("smoothOut", { type = "bezier", points = { { 0.36, 0 }, { 0.66, -0.56 } } })
hl.curve("smoothIn", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("softSnap", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
hl.curve("fluent", { type = "bezier", points = { { 0.0, 0.0 }, { 0.2, 1.0 } } })

---------------------
--   Animations    --
---------------------
-- Syntax: hl.animation({ leaf = "NAME", enabled = bool, speed = float, bezier = "NAME", style = "STR" })

-- Windows
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "smoothOut", style = "popin 95%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "softSnap" })

-- Layers
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "smoothIn", style = "slide right" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "softSnap", style = "slide right" })

-- Fade
-- Using a loop for repetitive fade settings to keep it dry
local fade_elements = { "fade", "fadeIn", "fadeOut", "fadeSwitch", "fadeShadow", "fadeDim", "fadeDpms" }
for _, element in ipairs(fade_elements) do
	local curve = element == "fadeOut" and "smoothOut" or "smoothIn"
	hl.animation({ leaf = element, enabled = true, speed = 4, bezier = curve })
end

-- Workspaces
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "overshot", style = "slidefade 30%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2, bezier = "overshot", style = "slidefadevert 30%" })
