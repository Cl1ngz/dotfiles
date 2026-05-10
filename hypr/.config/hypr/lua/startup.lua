-- █▀▀ ▀▄▀ █▀▀ █▀▀
-- ██▄ █░█ ██▄ █▄▄

local hl = require("hyprland")

hl.on("hyprland.start", function()
	-- Environment and DBUS (Essential for Wayland/Screensharing)
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	hl.exec_cmd("xdg-desktop-portal-hyprland")
	hl.exec_cmd("xdg-desktop-portal")

	-- System Services
	hl.exec_cmd("awww-daemon") -- Wallpapers
	hl.exec_cmd("waybar") -- Status bar
	hl.exec_cmd("dunst") -- Notifications
	hl.exec_cmd("blueman-applet") -- Bluetooth
	hl.exec_cmd("nm-applet --indicator") -- Network

	-- Clipboard Manager
	hl.exec_cmd("wl-paste --watch cliphist store")

	-- Idle Daemon (Keep your existing .conf)
	hl.exec_cmd("hypridle")

	-- Battery Alerts (Batsignal)
	hl.exec_cmd('batsignal -b -w 20 -c 10 -d 5 -e "paplay /usr/share/sounds/freedesktop/stereo/message.oga"')
end)
