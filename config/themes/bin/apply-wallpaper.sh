#!/usr/bin/env bash
# Set the wallpaper. Auto-detects image vs video:
#   image (.jpg/.png/.webp/.bmp)            -> swww    (static, transitions)
#   video (.mp4/.mkv/.webm/.gif/.mov/.avi)  -> mpvpaper (loops silently)
# Usage: apply-wallpaper.sh <path>
set -euo pipefail

# Fedora 43 renamed swww to awww. Prefer whichever this machine actually has,
# so the same script works on both.
if command -v swww >/dev/null 2>&1; then
    WW=swww; WW_DAEMON=swww-daemon
elif command -v awww >/dev/null 2>&1; then
    WW=awww; WW_DAEMON=awww-daemon
else
    echo "neither swww nor awww is installed" >&2; exit 1
fi

STATE="$HOME/.config/themes/state.json"
img="${1:-}"
[ -z "$img" ] && { echo "usage: apply-wallpaper.sh <path>"; exit 1; }
[ -f "$img" ] || { echo "no such file: $img"; exit 1; }

# any prior mpvpaper must go regardless of next type
pkill -x mpvpaper 2>/dev/null || true

ext="${img##*.}"; ext="${ext,,}"
case "$ext" in
    mp4|mkv|webm|gif|mov|avi|m4v)
        # video -> mpvpaper; swww-daemon must not be running or it blocks the layer-shell surface
        pkill -x "$WW_DAEMON" 2>/dev/null || true
        setsid mpvpaper -o "no-audio loop hwdec=auto" '*' "$img" >/dev/null 2>&1 < /dev/null &
        ;;
    *)
        # image -> swww (start daemon if needed, then set with a transition)
        if ! pgrep -x "$WW_DAEMON" >/dev/null 2>&1; then
            setsid "$WW_DAEMON" >/dev/null 2>&1 < /dev/null &
            sleep 0.4
        fi
        "$WW" img "$img" \
            --transition-type grow \
            --transition-pos 0.9,0.05 \
            --transition-fps 60 \
            --transition-duration 1.2
        ;;
esac

tmp="$(mktemp)"
[ -f "$STATE" ] || echo '{}' > "$STATE"
jq --arg w "$img" '.wallpaper = $w' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
echo "wallpaper: $img"

# Re-derive the whole colour scheme from the new wallpaper. This is what keeps
# the shell, borders and terminal in step without picking a theme by hand.
# Only in wallpaper mode — a manually chosen accent must survive a wallpaper change.
if [ "$(jq -r '.colorMode // "wallpaper"' "$HOME/.config/quickshell/settings.json" 2>/dev/null)" != "manual" ]; then
    "$HOME/.config/themes/bin/apply-colors.sh" --wallpaper || true
fi
