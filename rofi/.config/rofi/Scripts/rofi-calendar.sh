#!/usr/bin/env bash

# Toggle Logic: If the calendar window is already active, kill it immediately
if pgrep -f "calendar.rasi" >/dev/null; then
  pkill -f "calendar.rasi"
  exit 0
fi

# 1. Get current month and year
TITLE=$(date +'%B %Y')

# 2. Calendar math
FIRST_DAY=$(date -d "$(date +%Y-%m-01)" +%u)
DAYS_IN_MONTH=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%-d)
CURRENT_DAY=$(date +%-d)

# 3. Create grid items array
declare -a CAL_ITEMS

# Headers
CAL_ITEMS+=("Po" "Wt" "Śr" "Cz" "Pi" "So" "Ni")

# Empty padding days
for ((i = 1; i < FIRST_DAY; i++)); do
  CAL_ITEMS+=(" ")
done

# Days of the month
for ((i = 1; i <= DAYS_IN_MONTH; i++)); do
  CAL_ITEMS+=("$i")
done

# 4. Calculate today's index (0-based)
TODAY_INDEX=$((7 + FIRST_DAY - 1 + CURRENT_DAY - 1))

# 5. Launch Rofi with the dedicated calendar theme
printf "%s\n" "${CAL_ITEMS[@]}" | rofi -dmenu \
  -p "$TITLE" \
  -a "$TODAY_INDEX" \
  -selected-row "$TODAY_INDEX" \
  -x11 \
  -theme "$HOME/.config/rofi/calendar.rasi"
