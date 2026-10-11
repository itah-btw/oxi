#!/bin/sh
# Prints "Cpu: NN%" from /proc/stat jiffies vs the last run.
# First run only stores a snapshot and prints nothing.
state="${XDG_RUNTIME_DIR:-/tmp}/cpu-jiffies"
read -r _ u n s id io ir so _rest < /proc/stat
total=$((u + n + s + id + io + ir + so))
idle=$((id + io))
if [ -f "$state" ]; then
  read -r pt pi < "$state"
  dt=$((total - pt))
  di=$((idle - pi))
  if [ "$dt" -gt 0 ]; then printf 'Cpu: %d%%\n' "$(( 100 * (dt - di) / dt ))"; fi
fi
printf '%s %s\n' "$total" "$idle" > "$state"
