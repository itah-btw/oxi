#!/bin/sh
# Prints "BT: on" or "BT: off" for the oxwm bar.
# Short-circuit when the daemon is absent and cap the call: bluetoothctl can
# hang waiting for bluetoothd, and a hanging bar block freezes the oxwm loop.
if pgrep -x bluetoothd >/dev/null 2>&1 && timeout 2 bluetoothctl show 2>/dev/null | grep -qi 'Powered: yes'; then
  printf 'BT: on\n'
else
  printf 'BT: off\n'
fi
