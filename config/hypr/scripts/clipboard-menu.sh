#!/usr/bin/env bash
# Clipboard history menu (Ctrl+B) backed by cliphist + rofi.
#
# - Item list is ONLY clipboard entries; Enter pastes a clip (never clears).
# - On Enter: the item is put on the clipboard (so manual Ctrl+V still works)
#   AND auto-pasted into whatever window you were in before opening the menu.
# - Alt+C (hint shown by the search bar) clears all history, after a yes/no.

theme=~/.config/rofi/menu.rasi

# Remember the window we were working in BEFORE rofi steals focus.
active=$(hyprctl activewindow -j 2>/dev/null)
target_addr=$(printf '%s' "$active" | jq -r '.address // empty')
target_class=$(printf '%s' "$active" | jq -r '.class // empty')

choice=$(cliphist list \
            | rofi -dmenu -theme "$theme" -p "Clipboard" \
                   -mesg "  Alt+C   clear all history" \
                   -kb-custom-1 "Alt+c")
code=$?

# Alt+C -> confirm, then wipe everything.
if [ "$code" -eq 10 ]; then
    confirm=$(printf '%s\n' "No, keep it" "Yes, clear everything" \
                | rofi -dmenu -theme "$theme" -p "Wipe all clipboard history?")
    if [ "$confirm" = "Yes, clear everything" ]; then
        cliphist wipe
        notify-send -a Clipboard "Clipboard" "History cleared" 2>/dev/null
    fi
    exit 0
fi

# Esc / cancel, or nothing selected.
[ "$code" -ne 0 ] && exit 0
[ -z "$choice" ] && exit 0

# Put the chosen item on the clipboard (this is what Ctrl+V will use).
printf '%s\n' "$choice" | cliphist decode | wl-copy

# Auto-paste into the original window. Terminals use Ctrl+Shift+V, the rest Ctrl+V.
case "$target_class" in
    kitty|scratch-term|*[Aa]lacritty*|*[Kk]itty*|foot|*[Ww]ez[Tt]erm*|*[Gg]hostty*|*[Kk]onsole*|*[Tt]erminator*|*[Tt]ilix*|xterm|URxvt|st-256color)
        mods="CTRL SHIFT" ;;
    *)
        mods="CTRL" ;;
esac

if [ -n "$target_addr" ]; then
    # Small pause so the clipboard is served and focus has settled.
    sleep 0.08
    hyprctl dispatch sendshortcut "$mods, V, address:$target_addr" >/dev/null 2>&1
fi
