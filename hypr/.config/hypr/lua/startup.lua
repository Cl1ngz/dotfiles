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
		'batsignal -b -w 20 -c 10 -d 5 -e "paplay /usr/share/sounds/freedesktop/stereo/message.oga"',
	}

	for _, app in ipairs(apps) do
		hl.exec_cmd(app)
	end
end)

-- example of old exec
-- hl.exec_cmd("notify-send 'Hyprland' 'Config Reloaded Successfully'")
