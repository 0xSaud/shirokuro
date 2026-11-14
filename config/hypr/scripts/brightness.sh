#!/usr/bin/env bash
# Single source of truth for brightness: applies AND saves every change, so the
# value survives reboots (restore-brightness.sh re-applies brightness.json at login).
#   the internal panel (auto-detected) -> brightnessctl   (absolute %)
#   external monitor      -> ddcutil VCP 10  (absolute 0-100)
#
# Usage:
#   brightness.sh up | down            relative on the monitor under the mouse
#                                       (moves BOTH if sync is on and an external exists)
#   brightness.sh laptop   <0-100>     absolute, laptop only
#   brightness.sh external <0-100>     absolute, external only
#   brightness.sh both     <0-100>     absolute, both screens
#   brightness.sh laptop-rel   <±N>    relative, laptop only
#   brightness.sh external-rel <±N>    relative, external only
#   brightness.sh sync                 toggle the sync flag (and match external to laptop)

# The internal panel is not called eDP-1 on every machine (eDP-2, LVDS-1, ...).
# Ask Hyprland for the first output whose name looks like a built-in panel and
# fall back to eDP-1 so behaviour is unchanged on the original hardware.
internal_panel() {
  hyprctl monitors -j 2>/dev/null \
    | jq -r '[.[].name] | map(select(test("^(eDP|LVDS|DSI)"))) | .[0] // "eDP-1"' 2>/dev/null \
    || echo eDP-1
}
INTERNAL="$(internal_panel)"
set -euo pipefail
step=10
STATE="$HOME/.config/themes/brightness.json"
[ -f "$STATE" ] || echo '{"laptop":50,"external":50,"sync":false}' > "$STATE"

clamp() { local v=$1; (( v < 5 )) && v=5; (( v > 100 )) && v=100; echo "$v"; }
get()   { jq -r --arg k "$1" '.[$k] // empty' "$STATE"; }
# If the state file is ever unparseable, jq fails and the save silently does
# nothing — brightness would apply but never persist. Rebuild it in that case.
save()  {
    local tmp; tmp="$(mktemp)"
    jq -e . "$STATE" >/dev/null 2>&1 || echo '{"laptop":50,"external":50,"sync":false}' > "$STATE"
    if jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$STATE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$STATE"
    else
        rm -f "$tmp"
    fi
}

apply_laptop()   { brightnessctl set "${1}%" >/dev/null 2>&1 || true; save laptop "$1"; }
apply_external() { ddcutil setvcp 10 "$1"    >/dev/null 2>&1 || true; save external "$1"; }

has_external() { hyprctl monitors -j 2>/dev/null | jq -e --arg int "$INTERNAL" '[.[].name] | any(. != $int)' >/dev/null 2>&1; }
sync_on()      { [ "$(jq -r '.sync // false' "$STATE")" = "true" ]; }

cmd="${1:-up}"
case "$cmd" in
    up|down)
        delta=$step; [ "$cmd" = down ] && delta=$(( -step ))
        # which monitor is the cursor on
        pos="$(hyprctl cursorpos 2>/dev/null || echo '0, 0')"
        cx="${pos%%,*}"; cx="${cx//[^0-9-]/}"; cy="${pos##*,}"; cy="${cy//[^0-9-]/}"
        : "${cx:=0}" "${cy:=0}"
        mon="$(hyprctl monitors -j 2>/dev/null | jq -r --argjson x "$cx" --argjson y "$cy" \
              '.[] | select($x>=.x and $x<(.x+.width) and $y>=.y and $y<(.y+.height)) | .name' | head -1)"
        [ -z "$mon" ] && mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[]|select(.focused==true)|.name' | head -1)"

        if sync_on && has_external; then
            v="$(clamp $(( $(get laptop) + delta )))"; apply_laptop "$v"; apply_external "$v"
        elif [ "$mon" = "$INTERNAL" ]; then
            v="$(clamp $(( $(get laptop) + delta )))"; apply_laptop "$v"
        else
            v="$(clamp $(( $(get external) + delta )))"; apply_external "$v"
        fi
        ;;
    laptop)       apply_laptop   "$(clamp "${2:-50}")" ;;
    external)     apply_external "$(clamp "${2:-50}")" ;;
    both)         v="$(clamp "${2:-50}")"; apply_laptop "$v"; apply_external "$v" ;;
    laptop-rel)   apply_laptop   "$(clamp $(( $(get laptop)   + ${2:-10} )))" ;;
    external-rel) apply_external "$(clamp $(( $(get external) + ${2:-10} )))" ;;
    sync)
        if sync_on; then
            save sync false
        else
            save sync true
            apply_external "$(get laptop)"   # entering sync: match monitor to laptop
        fi
        ;;
    *) echo "usage: brightness.sh {up|down|laptop N|external N|both N|laptop-rel ±N|external-rel ±N|sync}" >&2; exit 1 ;;
esac
