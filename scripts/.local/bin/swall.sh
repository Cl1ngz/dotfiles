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

# 3. Run Matugen
matugen image "$1" --mode dark --source-color-index 0

# 4. Refresh the stubborn apps (Silenly in background)
thunar -q && thunar --daemon &

# Kill existing applets/bar
killall waybar 2>/dev/null

# Restart and detach from terminal
waybar >/dev/null 2>&1 &

# Reload Hyprland
hyprctl reload

notify-send "Theme Applied" "Wallpaper and colors updated!" -i "$1"
