#!/bin/sh
# Prints the hottest thermal zone, e.g. "Temp: 52°C".
# NOTE: shell builtins only (no `cat` fork per zone) - this runs
# synchronously on oxwm's main loop, so every forked process
# here is input latency for the whole session.
best=0
for f in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$f" ] || continue
  IFS= read -r t < "$f" || continue
  case "$t" in
    *[!0-9]*|"") continue ;;
  esac
  [ "$t" -gt "$best" ] && best=$t
done
[ "$best" -gt 0 ] || exit 0
printf 'Temp: %d°C\n' "$((best / 1000))"
