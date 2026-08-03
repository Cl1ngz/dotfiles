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
thunar -q 2>/dev/null; thunar --daemon &

# 5. Tell quickshell to reload, explicitly.
#
# It does watch its config dir, but a generated Colors.qml can be seen
# mid-write: the reload then fails and the old colours stay. An IPC call
# after matugen has finished is deterministic. The handler lives in
# bar.qml (target "theme").
#
# `qs` and `quickshell` are the same binary; try whichever exists.
QS_DIR="$HOME/.config/quickshell"
QS_BIN=$(command -v qs || command -v quickshell)
if [ -n "$QS_BIN" ]; then
  sleep 0.3
  "$QS_BIN" -p "$QS_DIR/bar.qml" ipc call theme reload >/dev/null 2>&1 \
    || touch "$QS_DIR/bar.qml"   # fall back to nudging the file watcher
fi

# 6. Reload Hyprland (picks up the regenerated colors.lua)
hyprctl reload

notify-send "Theme Applied" "Wallpaper and colors updated!" -i "$1"
