#!/bin/sh
# Prints "Bright: NN%" for notifications.
for dev in /sys/class/backlight/*; do
  [ -r "$dev/brightness" ] && [ -r "$dev/max_brightness" ] || continue
  cur=$(cat "$dev/brightness")
  max=$(cat "$dev/max_brightness")
  [ "${max:-0}" -gt 0 ] 2>/dev/null || continue
  printf 'Bright: %d%%\n' "$(( 100 * cur / max ))" && exit 0
done
exit 0
