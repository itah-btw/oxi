#!/bin/sh
# Prints "Wifi: <SSID>" or "Wifi: off" for the oxwm bar.
# NOTE: `nmcli dev wifi` triggers a radio rescan (up to seconds
# of stall on oxwm's main loop); `device status` only reads
# NetworkManager state, never touching the radio.
ssid=$(nmcli -t -f TYPE,CONNECTION device status 2>/dev/null | sed -n 's/^wifi://p' | head -n 1)
if [ -n "$ssid" ]; then
  printf 'Wifi: %s\n' "$ssid"
else
  printf 'Wifi: off\n'
fi
