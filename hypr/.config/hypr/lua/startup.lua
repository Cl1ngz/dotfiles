-- █▀▀ ▀▄▀ █▀▀ █▀▀
-- ██▄ █░█ ██▄ █▄▄

hl.on("hyprland.start", function()
	local apps = {
		-- Environment and DBUS
		"dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
		"dbus-update-activation-environment --systemd --all",
		"xdg-desktop-portal-hyprland",
		"xdg-desktop-portal",

		-- System Services
		"awww-daemon",
		"waybar",
		"dunst",
		"blueman-applet",
		"nm-applet --indicator",

		-- Clipboard Manager
		"wl-paste --watch cliphist store",

		-- Idle Daemon
		"hypridle",

		-- Battery Alerts (Batsignal)
		"batsignal -b -w 20 -c 10 -d 5",

		-- Custom Startup Apps
		"bash -c 'sleep 2 && keepassxc'",
		"zen-browser",
	}

	for _, app in ipairs(apps) do
		hl.exec_cmd(app)
	end
end)

-- example of old exec this is the replacment
-- hl.exec_cmd("notify-send 'Hyprland' 'Config Reloaded Successfully'")
