#!/usr/bin/env bash

if [ -z "$1" ]; then
  echo "Usage: swall.sh /path/to/image.jpg"
  exit 1
fi

WALL_DIR="$HOME/.config/hypr/wallpaper"
mkdir -p "$WALL_DIR"

# 1. Create a permanent symlink
ln -sf "$(realpath "$1")" "$WALL_DIR/current_wall"

# 2. Set the wallpaper
awww img "$WALL_DIR/current_wall"

# 3. Run Matugen (rewrites ~/.config/quickshell/Colors.qml among others)
matugen image "$1" --mode dark --source-color-index 0

# 4. Refresh the stubborn apps (silently, in background)
# ';' not '&&': if the daemon wasn't running, -q fails and '&&' would
# have skipped the restart.
thunar -q 2>/dev/null
thunar --daemon &

# IF i ever need to come back to this
# Kill existing applets/bar
# killall waybar 2>/dev/null

# Restart and detach from terminal
# waybar >/dev/null 2>&1 &

# 5. The quickshell bar recolors itself: it watches its config files
# and hot-reloads when matugen rewrites Colors.qml. No restart needed.
#
# If your quickshell build turns out not to live-reload, uncomment this
# fallback. It restarts ONLY the bar (matching on bar.qml), never the
# clipboard/powermenu/wallpaper panels:
# pkill -f 'quickshell -p .*bar.qml' 2>/dev/null
# quickshell -p "$HOME/.config/quickshell/bar.qml" >/dev/null 2>&1 &

# 6. Reload Hyprland (picks up the regenerated colors.lua)
hyprctl reload

notify-send "Theme Applied" "Wallpaper and colors updated!" -i "$1"
