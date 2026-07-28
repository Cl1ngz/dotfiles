-- █▄▀ █▀▀ █▄█ █▄▄ █ █▄░█ █▀▄
-- █░█ ██▄ ░█░ █▄█ █ █░▀█ █▄▀
local mainMod = "SUPER"

-- Helper variables for paths
local custom_scripts = os.getenv("HOME") .. "/Documents/Scripts"

-- █▀ █▀▀ █▀█ █▀▀ █▀▀ █▄░█ █▀ █░█ █▀█ ▀█▀
-- ▄█ █▄▄ █▀▄ ██▄ ██▄ █░▀█ ▄█ █▀█ █▄█ ░█░
hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'))

-- █   ▄▀▄ █ █ █▄ █ ▄▀▀ █▄█ ██▀ █▀▄
-- █▄▄ █▀█ ▀▄█ █ ▀█ ▀▄▄ █ █ █▄▄ █▀▄
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/wallpapers.qml "))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/launcher.qml"))
hl.bind("ALT + V", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/clipboard.qml"))

-- █   █ █ █▄ █ █▀▄ ▄▀▄ █   █   █▄ ▄█ ▄▀▄ █▄ █ ▄▀▄ ▄▀  █▄ ▄█ ██▀ █▄ █ ▀█▀
-- ▀▄▀▄▀ █ █ ▀█ █▄▀ ▀▄▀ ▀▄▀▄▀   █ ▀ █ █▀█ █ ▀█ █▀█ ▀▄█ █ ▀ █ █▄▄ █ ▀█  █
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/powermenu.qml"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())

hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(0))
hl.bind(mainMod .. " + Space", hl.dsp.window.float({ action = "toggle" }))

-- █   █ ▄▀▄ █▀▄ █▄▀ ▄▀▀ █▀▄ ▄▀▄ ▄▀▀ ██▀   █▄ ▄█ ▄▀▄ █▀▄ ██▀ ▄▀▀
-- ▀▄▀▄▀ ▀▄▀ █▀▄ █ █ ▄██ █▀  █▀█ ▀▄▄ █▄▄   █ ▀ █ ▀▄▀ █▄▀ █▄▄ ▄██
hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.exec_cmd("hyprctl dispatch workspaceopt allfloat"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprctl dispatch workspaceopt allpseudo"))

-- Cycle focus
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ window = "next" }))
hl.bind(mainMod .. " + Tab", hl.dsp.window.bring_to_top())

---------------------
-- Navigation & Resizing --
---------------------

-- Move Focus
local dirs = { left = "l", right = "r", up = "u", down = "d" }
for key, dir in pairs(dirs) do
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

-- █▀▄ ██▀ ▄▀▀ █ ▀█▀ ██▀
-- █▀▄ █▄▄ ▄██ █ █▄▄ █▄▄
hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.resize({ x = -20, y = 0 }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 20, y = 0 }))
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.resize({ x = 0, y = -20 }))
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.resize({ x = 0, y = 20 }))

-- █   █ ▄▀▄ █▀▄ █▄▀ ▄▀▀ █▀▄ ▄▀▄ ▄▀▀ ██▀   █▄ █ ▄▀▄ █ █
-- ▀▄▀▄▀ ▀▄▀ █▀▄ █ █ ▄██ █▀  █▀█ ▀▄▄ █▄▄   █ ▀█ █▀█ ▀▄▀
for i = 1, 10 do
	local key = i % 10
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Relative Workspace Switching
hl.bind(mainMod .. " + ALT + up", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + ALT + down", hl.dsp.focus({ workspace = "e-1" }))

-- █▄ ▄█ ▄▀▄ █ █ ▄▀▀ ██▀   ██▄ █ █▄ █ █▀▄
-- █ ▀ █ ▀▄▀ ▀▄█ ▄██ █▄▄   █▄█ █ █ ▀█ █▄▀
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

---------------------
--  Monitor Move   --
---------------------
hl.bind(mainMod .. " + CTRL + 1", hl.dsp.exec_cmd(custom_scripts .. "/move_workspace.sh 1"))
hl.bind(mainMod .. " + CTRL + 2", hl.dsp.exec_cmd(custom_scripts .. "/move_workspace.sh 2"))

-- █▄ ▄█ █ █ █   ▀█▀ █ █▄ ▄█ ██▀ █▀▄ █ ▄▀▄   █▄▀ ██▀ ▀▄▀ ▄▀▀
-- █ ▀ █ ▀▄█ █▄▄  █  █ █ ▀ █ █▄▄ █▄▀ █ █▀█   █ █ █▄▄  █  ▄██
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s 5%+"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 5%-"))
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q -d '*kbd_backlight*' s 10%+"))
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q -d '*kbd_backlight*' s 10%-"))

-- Player Controls
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
