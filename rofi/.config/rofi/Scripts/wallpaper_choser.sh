#!/usr/bin/env bash

# CONFIGURATION
WALL_DIR="$HOME/Pictures/Wallpapers"
CACHE_DIR="$HOME/.cache/wallpaper-thumbs"
ROFI_THEME="$HOME/dotfiles/rofi/.config/rofi/wallpaper-grid.rasi"

mkdir -p "$CACHE_DIR"

# Get list of categories (folders)
CATEGORIES=($(ls -d "$WALL_DIR"/*/ | xargs -n1 basename))
current_idx=0

# Logic to handle Tab (switching folders)
choose_wallpaper() {
  local category=${CATEGORIES[$current_idx]}
  local current_path="$WALL_DIR/$category"

  # Generate icons for rofi
  local input_string=""
  while IFS= read -r img; do
    thumb="$CACHE_DIR/$(basename "$img")"
    # Generate thumbnail if it doesn't exist
    [[ ! -f "$thumb" ]] && magick "$img" -strip -thumbnail 400x400^ -gravity center -extent 400x400 "$thumb"
    input_string+="$(basename "$img")\0icon\x1f$thumb\n"
  done < <(find "$current_path" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \))

  # Run Rofi
  selected=$(echo -en "$input_string" | rofi -dmenu -i -p "󰸉 $category" \
    -theme "$ROFI_THEME" \
    -kb-row-next "" \
    -kb-element-next "" \
    -kb-custom-1 "Tab" \
    -show-icons)

  exit_code=$?

  if [ $exit_code -eq 10 ]; then
    # Tab was pressed: Cycle to next folder
    current_idx=$(((current_idx + 1) % ${#CATEGORIES[@]}))
    choose_wallpaper
  elif [ -n "$selected" ]; then
    # Image was selected
    swall.sh "$current_path/$selected"
  fi
}

choose_wallpaper
