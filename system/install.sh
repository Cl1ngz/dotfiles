#!/usr/bin/env bash
#
# Installs the system-level parts of these dotfiles.
#
# Everything else in this repo is stowed into $HOME. These two files
# belong under /etc, which is a different target root and needs root to
# write, so they are copied rather than symlinked -- that also avoids
# root reading config through symlinks into /home at boot.
#
# Usage:  ./system/install.sh
# Re-run it after editing either file.

set -euo pipefail

# Resolve the directory this script lives in, so it works from anywhere.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user; it calls sudo where needed." >&2
  exit 1
fi

echo ":: udev rule (passwordless battery charge limit writes)"
sudo install -Dm644 \
  "$here/etc/udev/rules.d/99-battery-charge-threshold.rules" \
  /etc/udev/rules.d/99-battery-charge-threshold.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=power_supply

# Seed the limit file BEFORE enabling the unit: the unit reads it on
# start, and with `set -e` a failed start would abort this script before
# the file ever got written.
limit_file="$HOME/.config/battery-charge-limit"
if [[ ! -f "$limit_file" ]]; then
  mkdir -p "$(dirname "$limit_file")"
  echo 80 > "$limit_file"
  echo ":: seeded $limit_file with 80 (change it from the bar's battery panel)"
fi

echo ":: systemd unit (re-apply charge limit at boot and after resume)"
# The unit runs as root at boot, so it cannot resolve $HOME itself --
# bake this user's real path in as the file is copied. Using | as the
# sed delimiter keeps paths containing / from breaking the expression.
sed "s|__LIMIT_FILE__|$limit_file|" \
  "$here/etc/systemd/system/battery-charge-limit.service" \
  | sudo install -Dm644 /dev/stdin /etc/systemd/system/battery-charge-limit.service
sudo systemctl daemon-reload
# Machines with no battery threshold make this a no-op; don't abort.
sudo systemctl enable --now battery-charge-limit.service || \
  echo ":: unit did not start cleanly -- check: systemctl status battery-charge-limit.service"

echo
echo "done. verify with:"
echo "  stat -c '%U %G %a' /sys/class/power_supply/BAT*/charge_control_end_threshold"
echo "  systemctl status battery-charge-limit.service"
echo "  grep LIMIT_FILE /etc/systemd/system/battery-charge-limit.service"
