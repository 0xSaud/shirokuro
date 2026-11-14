#!/usr/bin/env bash
# Wallpaper manager — images (static) + videos (live, via mpvpaper).
#   Enter  -> set as wallpaper
#   Alt+x  -> delete the highlighted wallpaper (with confirm)
#   top row "Add new wallpaper…" -> file picker to import a new image or video
pgrep -x rofi >/dev/null 2>&1 && { killall rofi; exit 0; }

WD="$HOME/Pictures/Wallpapers"
TH="$HOME/.cache/wallpaper-thumbs"
mkdir -p "$WD" "$TH"
ADD="  Add new wallpaper…"
APPLY="$HOME/.config/themes/bin/apply-wallpaper.sh"

# generate (or reuse cached) a thumbnail for a video file
vid_thumb() {
    local src="$1" base name out
    name="$(basename "$src")"
    out="$TH/${name}.png"
    if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
        ffmpeg -y -ss 00:00:01 -i "$src" -frames:v 1 -vf "scale=320:-1" "$out" \
               >/dev/null 2>&1 \
        || ffmpeg -y -i "$src" -frames:v 1 -vf "scale=320:-1" "$out" \
               >/dev/null 2>&1 || true
    fi
    printf '%s' "$out"
}

gen() {
    printf '%s\n' "$ADD"
    for f in "$WD"/*; do
        [ -f "$f" ] || continue
        local lc="${f,,}" thumb=""
        case "$lc" in
            *.jpg|*.jpeg|*.png|*.webp|*.bmp)
                thumb="$f" ;;
            *.mp4|*.mkv|*.webm|*.gif|*.mov|*.avi|*.m4v)
                thumb="$(vid_thumb "$f")" ;;
            *) continue ;;
        esac
        # tag videos in the label with a small marker; icon is image or video-frame thumb
        local label
        label="$(basename "$f")"
        case "$lc" in *.mp4|*.mkv|*.webm|*.mov|*.avi|*.m4v) label="▶ $label" ;; esac
        printf '%s\0icon\x1f%s\n' "$label" "$thumb"
    done
}

while true; do
    sel=$(gen | rofi -dmenu -i -show-icons -p "Wallpaper" \
            -mesg "Enter: set   ·   Alt+x: delete   ·   top row: add (image / video)" \
            -kb-custom-1 "Alt+x" \
            -theme ~/.config/rofi/wall.rasi)
    code=$?

    [ "$code" -eq 1 ] && exit 0
    [ -z "$sel" ] && exit 0
    base="${sel#▶ }"   # strip our video marker

    if [ "$sel" = "$ADD" ]; then
        src=$(zenity --file-selection --title="Pick an image or video to add" \
              --file-filter='Wallpapers | *.jpg *.jpeg *.png *.webp *.bmp *.gif *.mp4 *.mkv *.webm *.mov *.avi *.m4v' \
              2>/dev/null) || exit 0
        [ -z "$src" ] && exit 0
        cp -f "$src" "$WD/$(basename "$src")"
        "$APPLY" "$WD/$(basename "$src")"
        exit 0
    fi

    if [ "$code" -eq 10 ]; then
        confirm=$(printf 'No, keep it\nYes, delete it' \
                  | rofi -dmenu -i -p "Delete $base ?" -theme ~/.config/rofi/menu.rasi)
        if [ "$confirm" = "Yes, delete it" ]; then
            rm -f -- "$WD/$base"
            rm -f -- "$TH/$base.png"   # cached thumbnail too
        fi
        continue
    fi

    "$APPLY" "$WD/$base"
    exit 0
done
