-- █░█░█ █ █▄░█ █▀▄ █▀█ █░█░█   █▀█ █░█ █░░ █▀▀ █▀
-- ▀▄▀▄▀ █ █░▀█ █▄▀ █▄█ ▀▄▀▄▀   █▀▄ █▄█ █▄▄ ██▄ ▄█

---------------------
--  Opacity Rules  --
---------------------
local opacities = {
	{ class = "^(kitty)$", active = 0.75, inactive = 0.75 },
	{ class = "^(discord)$", active = 0.71, inactive = 0.71 },
	{ class = "^(code-oss)$", active = 0.91, inactive = 0.91 },
	{ class = "^(jetbrains-idea-ce)$", active = 0.9, inactive = 0.9 },
	{ class = "^(rofi)$", active = 0.8, inactive = 0.6 },
}

for _, rule in ipairs(opacities) do
	hl.window_rule({
		match = { class = rule.class },
		opacity = rule.active .. " " .. rule.inactive,
	})
end

---------------------
-- Floating Rules  --
---------------------
local floating_apps = {
	{ class = "pavucontrol" },
	{ class = "blueman-manager" },
	{ class = "nm-connection-editor" },
	{ class = "chromium" },
	{ title = "btop" },
	{ title = "update-sys" },
	{ title = "Oracle VM VirtualBox Manager" },
	{ title = "VirtualBox - Preferences" },
	{ class = "steam" },
	{ class = "imv" },
}

for _, app in ipairs(floating_apps) do
	hl.window_rule({
		match = app,
		float = true,
	})
end

---------------------
-- Workspace Rules --
---------------------
local workspaces = {
	[2] = { "zen" },
	[3] = { "thunar" },
	[4] = { "dev.zed.Zed", "jetbrains-idea" },
	[5] = { "vesktop", "calibre-gui" },
	[6] = { "obsidian", "localsend" },
	[7] = { "virt-manager" },
	[8] = { "thunderbird", "org.qbittorrent.qBittorrent" },
	[9] = { "superProductivity" },
	[10] = { "KeePassXC", "org.keepassxc.KeePassXC" },
}

for ws, apps in pairs(workspaces) do
	for _, app in ipairs(apps) do
		hl.window_rule({
			match = { class = app },
			workspace = tostring(ws),
		})
	end
end

---------------------
-- Specific Rules  --
---------------------

-- Rofi Tweaks
hl.window_rule({
	match = { class = "^(rofi)$" },
	move = "-3% -105%",
	no_anim = true,
})

-- IMV image viewer sizing
hl.window_rule({
	match = { class = "imv" },
	center = true,
	size = "900 600",
})

-- Steam / Friends List
hl.window_rule({
	match = { title = "Friends List" },
	size = "380 720",
})

-- Fullscreen apps
hl.window_rule({
	match = { class = "^(superProductivity)$" },
	fullscreen = true,
})

-- XWayland Video Bridge (Invisible Helper)
hl.window_rule({
	match = { class = "xwaylandvideobridge" },
	opacity = "0.0 override 0.0 override",
	no_anim = true,
	no_focus = true,
	no_initial_focus = true,
})

---------------------
-- Complex Objects --
---------------------

-- Fix XWayland Drags
hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

-- Hyprland-run placement
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})
