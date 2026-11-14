#!/usr/bin/env bash
# Toggle a dropdown window on a special workspace; (re)spawn it if it was closed.
#   Usage: scratchpad.sh <special-name> <window-class> <command...>
# e.g.  scratchpad.sh scratch scratch-term kitty --class scratch-term
sp="$1"; class="$2"; shift 2

exists=$(hyprctl clients -j | jq --arg c "$class" 'any(.[]; .class==$c)' 2>/dev/null)
shown=$(hyprctl monitors -j | jq --arg s "special:$sp" 'any(.[]; .specialWorkspace.name==$s)' 2>/dev/null)

if [ "$exists" != "true" ]; then
    # window was closed (or never opened) -> spawn it hidden on its special workspace
    hyprctl dispatch exec "[workspace special:$sp silent] $*"
    # reveal it unless that special workspace is already on screen
    [ "$shown" = "true" ] || hyprctl dispatch togglespecialworkspace "$sp"
else
    # window exists -> just show/hide it
    hyprctl dispatch togglespecialworkspace "$sp"
fi
