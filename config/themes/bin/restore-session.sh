#!/usr/bin/env bash
# Restore the saved wallpaper + colour scheme. Run once at Hyprland startup.
#
# Colours are owned by apply-colors.sh (Material 3, generated from the wallpaper
# or from a chosen source colour). apply-theme.sh is deliberately NOT called
# here any more: it re-applied the old named theme on every login, and in manual
# colour mode nothing overwrote it afterwards — which is where the stray green
# was coming from.
set -euo pipefail

BIN="$HOME/.config/themes/bin"
STATE="$HOME/.config/themes/state.json"
[ -f "$STATE" ] || echo '{}' > "$STATE"

wall="$(jq -r '.wallpaper // empty' "$STATE")"
if [ -n "$wall" ] && [ -f "$wall" ]; then
    "$BIN/apply-wallpaper.sh" "$wall" || true
fi

# Always regenerate, so both colour modes land correctly:
#   wallpaper mode -> derived from the image just restored
#   manual mode    -> the source colour saved in settings.json
"$BIN/apply-colors.sh" || true

"$BIN/restore-brightness.sh" 2>/dev/null || true
