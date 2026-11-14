#!/usr/bin/env bash
# Themed power menu. Toggles closed if rofi is already open.
pgrep -x rofi >/dev/null 2>&1 && { killall rofi; exit 0; }

opt=$(printf '  Lock\n  Suspend\n  Logout\n  Reboot\n  Shutdown' \
      | rofi -dmenu -i -p "Power" -theme ~/.config/rofi/menu.rasi)

case "$opt" in
    *Lock*)
        # hyprlock = the actual screen locker (loginctl lock-session does nothing without one)
        setsid hyprlock -q >/dev/null 2>&1 < /dev/null &
        ;;
    *Suspend*)
        # -i ignores inhibitors (Discord/Brave/etc. that block sleep)
        systemctl suspend -i || loginctl suspend -i 2>/dev/null
        ;;
    *Logout*)
        # exit Hyprland -> back to SDDM; fall back to killing the user session if needed
        hyprctl dispatch exit 2>/dev/null || loginctl terminate-user "$USER"
        ;;
    *Reboot*)
        systemctl reboot
        ;;
    *Shutdown*)
        systemctl poweroff
        ;;
esac
