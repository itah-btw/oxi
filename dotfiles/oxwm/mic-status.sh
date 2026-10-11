#!/bin/sh
# Prints "Mic: live" or "Mic: muted" for notifications.
vol=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null) || exit 0
case "$vol" in
  *MUTED*) printf 'Mic: muted\n' ;;
  Volume:*) printf 'Mic: live\n' ;;
esac
