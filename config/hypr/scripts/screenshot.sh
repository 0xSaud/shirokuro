#!/usr/bin/env bash
# Screenshot helper for Hyprland
# Modes:
#   region   - select an area, open in swappy to annotate/crop, copy + save
#   window   - capture the focused window, copy + save
#   screen   - capture the whole focused monitor, copy + save
#   regioncp - select an area, copy to clipboard only (no file, no editor)
# Saves PNGs to ~/Pictures/Screenshots and always copies to the clipboard.

set -euo pipefail

mode="${1:-region}"
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +'%Y-%m-%d_%H-%M-%S').png"

notify() { command -v notify-send >/dev/null 2>&1 && timeout 2 notify-send -a Screenshot "$@" 2>/dev/null || true; }

case "$mode" in
  region)
    geom="$(slurp 2>/dev/null)" || exit 0   # cancelled with Esc
    if command -v swappy >/dev/null 2>&1; then
      # Grab into a temp file only. Clipboard gets the raw shot immediately so
      # paste-workflows still work. Nothing lands in ~/Pictures/Screenshots
      # unless you press Save (Ctrl+S) in swappy; closing the window (X/Esc)
      # discards it. Save target comes from ~/.config/swappy/config save_dir.
      tmp="$(mktemp --suffix=.png)"
      trap 'rm -f "$tmp"' EXIT
      grim -g "$geom" - | tee "$tmp" | wl-copy
      swappy -f "$tmp"
    else
      # No annotator available: fall back to saving straight to disk.
      grim -g "$geom" - | tee "$file" | wl-copy
      notify "Region saved" "$file"
    fi
    ;;
  window)
    geom="$(hyprctl -j activewindow | grep -oP '(?<="at": \[)[^]]*' )"
    size="$(hyprctl -j activewindow | grep -oP '(?<="size": \[)[^]]*')"
    x="${geom%%,*}"; y="${geom##*, }"
    w="${size%%,*}"; h="${size##*, }"
    grim -g "${x},${y} ${w}x${h}" - | tee "$file" | wl-copy
    notify "Window saved" "$file"
    ;;
  screen)
    grim - | tee "$file" | wl-copy
    notify "Screen saved" "$file"
    ;;
  regioncp)
    geom="$(slurp 2>/dev/null)" || exit 0
    grim -g "$geom" - | wl-copy
    notify "Region copied" "Clipboard only"
    ;;
  *)
    echo "usage: $0 {region|window|screen|regioncp}" >&2
    exit 1
    ;;
esac
