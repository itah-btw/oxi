#!/bin/sh
# Prints "Vol: NN%" or "MUTED" for the oxwm bar. oxwm draws each
# block in one static color (no markup/ANSI), so the state shows
# in the text itself.
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || exit 0
case "$vol" in
  *MUTED*) printf 'MUTED\n' ;;
  Volume:*) printf 'Vol: %d%%\n' "$(printf '%s' "$vol" | awk '{printf "%d", $2 * 100}')" ;;
esac
