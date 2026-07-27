-- █▄▀ █▀▀ █▄█ █▄▄ █ █▄░█ █▀▄
-- █░█ ██▄ ░█░ █▄█ █ █░▀█ █▄▀
local mainMod = "SUPER"

-- Helper variables for paths
local scripts = os.getenv("HOME") .. "/.config/waybar/scripts"
local rofi_scripts = os.getenv("HOME") .. "/.config/rofi/Scripts"
local custom_scripts = os.getenv("HOME") .. "/Documents/Scripts"

-- █▀ █▀▀ █▀█ █▀▀ █▀▀ █▄░█ █▀ █░█ █▀█ ▀█▀
-- ▄█ █▄▄ █▀▄ ██▄ ██▄ █░▀█ ▄█ █▀█ █▄█ ░█░
hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'))

-- █   ▄▀▄ █ █ █▄ █ ▄▀▀ █▄█ ██▀ █▀▄
-- █▄▄ █▀█ ▀▄█ █ ▀█ ▀▄▄ █ █ █▄▄ █▀▄
-- hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd(rofi_scripts .. "/wallpaper_choser.sh"))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/wallpapers.qml "))
-- hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("rofi -show drun"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/launcher.qml"))
-- hl.bind("ALT + V", hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy"))
hl.bind("ALT + V", hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/clipboard.qml"))

-- █   █ █ █▄ █ █▀▄ ▄▀▄ █   █   █▄ ▄█ ▄▀▄ █▄ █ ▄▀▄ ▄▀  █▄ ▄█ ██▀ █▄ █ ▀█▀
-- ▀▄▀▄▀ █ █ ▀█ █▄▀ ▀▄▀ ▀▄▀▄▀   █ ▀ █ █▀█ █ ▀█ █▀█ ▀▄█ █ ▀ █ █▄▄ █ ▀█  █
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
-- hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(rofi_scripts .. "/powermenu.sh"))
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
local media_keys = {
	XF86AudioRaiseVolume = "--inc",
	XF86AudioLowerVolume = "--dec",
	XF86AudioMicMute = "--toggle-mic",
	XF86AudioMute = "--toggle",
}

for key, arg in pairs(media_keys) do
	hl.bind(key, hl.dsp.exec_cmd(scripts .. "/volume " .. arg))
end

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(scripts .. "/brightness --inc"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scripts .. "/brightness --dec"))
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd(scripts .. "/kb-brightness --inc"))
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd(scripts .. "/kb-brightness --dec"))

-- Player Controls
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
