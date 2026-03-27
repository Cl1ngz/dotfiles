#!/usr/bin/env bash

# Options
uptime="$(uptime -p | sed -e 's/up //')"

# Standard icons from your reference
lock="󰌾"
logout="󰍃"
suspend="󰤄"
shutdown=""
reboot="󰜉"

options="$lock\n$logout\n$suspend\n$shutdown\n$reboot"

# We use higher padding (45px) and specific spacing to create the boxy look
chosen="$(echo -e "$options" | rofi -dmenu -i -p "Uptime: $uptime" \
  -theme-str 'window {width: 700px;} 
              listview {columns: 5; lines: 1; orientation: horizontal; spacing: 15px; margin: 10px;} 
              element {orientation: vertical; padding: 45px 0px; border-radius: 12px;} 
              element-text {font: "JetBrains Mono Nerd Font 48"; horizontal-align: 0.5;} 
              inputbar {children: [prompt];} 
              prompt {horizontal-align: 0.0; margin: 0 0 15px 10px; text-color: @fg;}' \
  -theme ~/.config/rofi/config.rasi)"

case $chosen in
$shutdown) systemctl poweroff ;;
$reboot) systemctl reboot ;;
$lock) loginctl lock-session ;;
$suspend) systemctl suspend ;;
$logout) hyprctl dispatch exit ;;
esac
