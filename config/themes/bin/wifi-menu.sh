#!/usr/bin/env bash
# Themed Wi-Fi picker (rofi + nmcli). Connect to known nets or prompt for a password.
pgrep -x rofi >/dev/null 2>&1 && { killall rofi; exit 0; }

list="$(nmcli -t -f IN-USE,SSID,SIGNAL device wifi list --rescan yes 2>/dev/null \
  | awk -F: 'NF && $2!="" { mark=($1=="*")?"  ":"   "; print mark $2 "   " $3 "%" }' \
  | awk '!seen[$0]++')"

sel="$(printf '%s\n  Wi-Fi off\n  Rescan' "$list" \
  | rofi -dmenu -i -p "Wi-Fi" -theme ~/.config/rofi/menu.rasi)"
[ -z "$sel" ] && exit 0

case "$sel" in
  *"Wi-Fi off") nmcli radio wifi off; exit 0 ;;
  *"Rescan")    exec "$0" ;;
esac

ssid="$(printf '%s' "$sel" | sed -E 's/^[* ]+//; s/   [0-9]+%$//')"
[ -z "$ssid" ] && exit 0
nmcli radio wifi on

if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "$ssid"; then
    nmcli connection up id "$ssid" >/dev/null 2>&1
else
    pass="$(: | rofi -dmenu -password -p "Password: $ssid" -theme ~/.config/rofi/menu.rasi)"
    if [ -n "$pass" ]; then
        nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1
    else
        nmcli device wifi connect "$ssid" >/dev/null 2>&1
    fi
fi
command -v notify-send >/dev/null 2>&1 \
  && notify-send -a "Wi-Fi" "Wi-Fi" "$ssid" 2>/dev/null || true
