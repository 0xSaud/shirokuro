#!/usr/bin/env bash
# GIF manager for the shell panels (Control Center header + music artwork
# fallback). Mirrors wallpaper-picker.sh.
#   Enter  -> use this GIF
#   Alt+x  -> delete the highlighted GIF (with confirm)
#   top rows -> add a new GIF, or turn the GIF off
pgrep -x rofi >/dev/null 2>&1 && { killall rofi; exit 0; }

GD="$HOME/Pictures/gifs"
TH="$HOME/.cache/gif-thumbs"
STATE="$HOME/.config/quickshell/gif.json"
mkdir -p "$GD" "$TH" "$(dirname "$STATE")"

ADD="  Add a GIF…"
OFF="  Turn GIF off"

# First frame of the GIF, cached, so rofi has something to show.
thumb() {
    local src="$1" out
    out="$TH/$(basename "$src").png"
    if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
        ffmpeg -y -i "$src" -frames:v 1 -vf "scale=320:-1" "$out" >/dev/null 2>&1 || true
    fi
    [ -f "$out" ] && printf '%s' "$out" || printf '%s' "$src"
}

gen() {
    printf '%s\n' "$ADD"
    printf '%s\n' "$OFF"
    for f in "$GD"/*; do
        [ -f "$f" ] || continue
        case "${f,,}" in
            *.gif|*.webp|*.png|*.jpg|*.jpeg|*.bmp|*.avif|*.tif|*.tiff|*.svg) ;;
            *) continue ;;
        esac
        printf '%s\0icon\x1f%s\n' "$(basename "$f")" "$(thumb "$f")"
    done
}

set_gif() {
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg p "$1" '{path:$p}' > "$STATE"
    else
        printf '{"path":"%s"}\n' "$1" > "$STATE"
    fi
}

while true; do
    sel=$(gen | rofi -dmenu -i -show-icons -p "GIF" \
            -mesg "Enter: use   ·   Alt+x: delete" \
            -kb-custom-1 "Alt+x" \
            -theme ~/.config/rofi/wall.rasi)
    code=$?

    [ "$code" -eq 1 ] && exit 0
    [ -z "$sel" ] && exit 0

    if [ "$sel" = "$ADD" ]; then
        src=$(zenity --file-selection --title="Pick a GIF" \
              --file-filter='Animated | *.gif *.webp *.png *.jpg *.jpeg *.bmp *.avif' 2>/dev/null) || exit 0
        [ -z "$src" ] && exit 0
        cp -f "$src" "$GD/$(basename "$src")"
        set_gif "$GD/$(basename "$src")"
        exit 0
    fi

    if [ "$sel" = "$OFF" ]; then
        set_gif ""
        exit 0
    fi

    if [ "$code" -eq 10 ]; then
        confirm=$(printf 'No, keep it\nYes, delete it' \
                  | rofi -dmenu -i -p "Delete $sel ?" -theme ~/.config/rofi/menu.rasi)
        if [ "$confirm" = "Yes, delete it" ]; then
            rm -f -- "$GD/$sel" "$TH/$sel.png"
            # If the deleted GIF was the one in use, stop pointing at it.
            cur=$(jq -r '.path // ""' "$STATE" 2>/dev/null)
            [ "$cur" = "$GD/$sel" ] && set_gif ""
        fi
        continue
    fi

    set_gif "$GD/$sel"
    exit 0
done
