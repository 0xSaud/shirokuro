#!/usr/bin/env bash
# Re-apply the last saved brightness for laptop + external. Called at login.
set -euo pipefail
STATE="$HOME/.config/themes/brightness.json"
[ -f "$STATE" ] || exit 0

lap="$(jq -r '.laptop  // empty' "$STATE")"
ext="$(jq -r '.external // empty' "$STATE")"

[ -n "$lap" ] && brightnessctl set "${lap}%" >/dev/null 2>&1 || true

if [ -n "$ext" ] && command -v ddcutil >/dev/null 2>&1; then
    # ddcutil can take a moment on cold boot; retry briefly if the bus isn't ready yet
    for _ in 1 2 3; do
        ddcutil setvcp 10 "$ext" >/dev/null 2>&1 && break
        sleep 1
    done
fi
