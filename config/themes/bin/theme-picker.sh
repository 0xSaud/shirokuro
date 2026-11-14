#!/usr/bin/env bash
# Pick a theme from a rofi menu and apply it everywhere.
pgrep -x rofi >/dev/null 2>&1 && { killall rofi; exit 0; }

THEMES="$HOME/.config/themes/themes"
STATE="$HOME/.config/themes/state.json"
cur=$(jq -r '.theme // "coffee"' "$STATE" 2>/dev/null)

list=""
for f in "$THEMES"/*.json; do
    n=$(basename "$f" .json)
    label=$(jq -r '.label' "$f")
    [ "$n" = "$cur" ] && label="$label   ✓"
    list+="$label"$'\n'
done

chosen=$(printf '%s' "$list" | rofi -dmenu -i -p "Theme" -theme ~/.config/rofi/menu.rasi)
[ -z "$chosen" ] && exit 0
chosen=${chosen%%   ✓}

for f in "$THEMES"/*.json; do
    if [ "$(jq -r '.label' "$f")" = "$chosen" ]; then
        "$HOME/.config/themes/bin/apply-theme.sh" "$(basename "$f" .json)"
        exit 0
    fi
done
