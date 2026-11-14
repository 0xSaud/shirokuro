#!/usr/bin/env bash
# Dual-screen master switch (END key).
# Toggles both monitors between the "home" layout and the "moved" layout.
#   home:   eDP-1 -> ws 1,  HDMI-A-1 -> ws 2
#   moved:  eDP-1 -> ws 11, HDMI-A-1 -> ws 12   (1-10 are ordinary workspaces)
# Direction is decided by the HIGHEST active workspace across ALL monitors,
# so it doesn't matter which monitor is focused when you press END.

log=/tmp/dual-screen-toggle.log

# Highest active workspace id across every monitor (defaults to 0 if jq fails).
max_ws=$(hyprctl monitors -j | jq '[.[].activeWorkspace.id] | max // 0')
[ -z "$max_ws" ] && max_ws=0

echo "$(date '+%H:%M:%S') fired; max_ws=$max_ws" >> "$log"

if [ "$max_ws" -ge 11 ]; then
    # Currently moved -> go back home.
    hyprctl dispatch focusmonitor HDMI-A-1
    hyprctl dispatch workspace 2
    hyprctl dispatch focusmonitor eDP-1
    hyprctl dispatch workspace 1
else
    # Currently home -> move away.
    hyprctl dispatch focusmonitor HDMI-A-1
    hyprctl dispatch workspace 12
    hyprctl dispatch focusmonitor eDP-1
    hyprctl dispatch workspace 11
fi
