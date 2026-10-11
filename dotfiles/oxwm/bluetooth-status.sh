#!/bin/sh
# Prints "BT: on" or "BT: off" for the oxwm bar.
if bluetoothctl show 2>/dev/null | grep -qi 'Powered: yes'; then
  printf 'BT: on\n'
else
  printf 'BT: off\n'
fi
