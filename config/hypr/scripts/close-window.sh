#!/usr/bin/env bash
# SUPER+C. Closes the focused window, except for "background" apps: those are
# tucked away on a hidden workspace so they keep running (music keeps playing),
# the way Discord keeps running in its tray.
#
# A hidden app keeps its icon on the bar, dimmed. Click the icon to bring the
# window back; right-click it and choose Quit to really close the app.
#
# To add another app, put its window class in the list below (lower case,
# separated by |). `hyprctl activewindow | grep class` shows a window's class.
BACKGROUND_APPS='spotify'

win=$(hyprctl activewindow -j 2>/dev/null)
class=$(jq -r '.class // ""' <<<"$win")
addr=$(jq -r '.address // ""' <<<"$win")

if [[ -n "$addr" && "${class,,}" =~ ^($BACKGROUND_APPS)$ ]]; then
    hyprctl dispatch movetoworkspacesilent "special:bg,address:$addr" >/dev/null
else
    hyprctl dispatch killactive >/dev/null
fi
