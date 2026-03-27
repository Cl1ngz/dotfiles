#!/bin/bash

# Check if the bottom bar is running
if pgrep -f "waybar -c /home/cl1ngz/.config/waybar/config-bottom.jsonc" > /dev/null; then
    # If running, kill it to hide the bar
    pkill -f "waybar -c /home/cl1ngz/.config/waybar/config-bottom.jsonc"
else
    # If not running, launch the bottom Waybar
    waybar -c ~/.config/waybar/config-bottom.jsonc -s ~/.config/waybar/style-bottom.css &
fi
