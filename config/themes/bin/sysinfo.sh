#!/usr/bin/env bash
# Emits "CPU%|MEM_GB|DISK_FREE|TEMP_C" once every 2s. Consumed by the Quickshell bar.
prev_total=0
prev_idle=0
while :; do
    # --- CPU % from /proc/stat deltas ---
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    idle_all=$(( idle + iowait ))
    total=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    dt=$(( total - prev_total ))
    di=$(( idle_all - prev_idle ))
    if [ "$dt" -gt 0 ]; then
        cpu=$(( (100 * (dt - di)) / dt ))
    else
        cpu=0
    fi
    prev_total=$total
    prev_idle=$idle_all
    [ "$cpu" -lt 0 ] && cpu=0
    [ "$cpu" -gt 100 ] && cpu=100

    # --- RAM used (GiB) ---
    mem=$(free -m | awk '/^Mem:/{printf "%.1f", $3/1024}')

    # --- Disk free on / ---
    disk=$(df -h --output=avail / | tail -1 | tr -d ' ')

    # --- Temperature (hottest thermal zone, °C) ---
    temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null \
           | sort -rn | head -1 | awk '{printf "%d", $1/1000}')

    echo "${cpu}|${mem:-0}|${disk:-?}|${temp:-0}"
    sleep 2
done
