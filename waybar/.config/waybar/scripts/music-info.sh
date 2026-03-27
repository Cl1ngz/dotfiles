#!/bin/bash

# 1. Get status details first
status=$(mpc status)

# 2. Exit only if MPD is totally empty/stopped (no song in queue)
if [[ -z "$status" || "$status" == "volume:"* ]]; then
  echo ""
  exit 0
fi

# 3. Get specific details
title=$(mpc current)
# Default title if mpc current is somehow empty but status exists
[ -z "$title" ] && title="No Title"

# Check if playing or paused
state=$(echo "$status" | grep -oP '\[\K[^\]]+')
# Get percentage (default to 0 if not found)
perc=$(echo "$status" | grep -oP '\(\K\d+(?=%\))')
[ -z "$perc" ] && perc=0

time_stat=$(echo "$status" | sed -n '2p' | awk '{print $3}')
[ -z "$time_stat" ] && time_stat="0:00/0:00"

# 4. Set dynamic icon
if [ "$state" == "playing" ]; then
  icon=""
else
  icon="󰏤" # This stays visible so you can click to resume!
fi

# 5. Generate the bar
draw_bar() {
  local p=$1
  local filled=$((p / 10))
  local empty=$((10 - filled))
  local bar=""
  for ((i = 0; i < filled; i++)); do bar+="━"; done
  for ((i = 0; i < empty; i++)); do bar+="─"; done
  echo "$bar"
}

bar_display=$(draw_bar "$perc")

# 6. Output JSON
tooltip_content="$title\n$time_stat ($state)"
echo "{\"text\": \"$icon $bar_display\", \"tooltip\": \"$tooltip_content\", \"class\": \"$state\"}"
