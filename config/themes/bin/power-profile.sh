#!/usr/bin/env bash
# GF63 power-profile switcher — drives tuned-ppd over the power-profiles-daemon
# D-Bus API. No root/sudo needed: polkit allows the active local session.
#
# UI names  <->  PPD names
#   eco         power-saver
#   balanced    balanced
#   performance performance
#
# Usage: power-profile.sh {get|eco|balanced|performance|cycle}
set -uo pipefail

DEST=net.hadess.PowerProfiles
OBJ=/net/hadess/PowerProfiles
IFACE=net.hadess.PowerProfiles

ui2ppd() { case "$1" in
    eco)         echo power-saver ;;
    performance) echo performance ;;
    *)           echo balanced ;;
  esac; }

ppd2ui() { case "$1" in
    power-saver) echo eco ;;
    performance) echo performance ;;
    *)           echo balanced ;;
  esac; }

get_ppd() {
  busctl --system get-property "$DEST" "$OBJ" "$IFACE" ActiveProfile 2>/dev/null \
    | sed -E 's/^s "?//; s/"?$//'
}

set_ui() {
  local ppd name ic
  ppd=$(ui2ppd "$1")
  busctl --system set-property "$DEST" "$OBJ" "$IFACE" ActiveProfile s "$ppd" >/dev/null 2>&1 || {
    notify-send -a Power "Power profile" "Switch failed (is tuned-ppd running?)" 2>/dev/null || true
    exit 1
  }
  name=$(ppd2ui "$ppd")
  case "$name" in
    eco)         ic=power-profile-power-saver-symbolic ;;
    performance) ic=power-profile-performance-symbolic ;;
    *)           ic=power-profile-balanced-symbolic ;;
  esac
  notify-send -a Power -i "$ic" "Power profile" "Switched to ${name^}" 2>/dev/null || true
}

case "${1:-get}" in
  get)                         ppd2ui "$(get_ppd)" ;;
  eco|balanced|performance)    set_ui "$1" ;;
  cycle)
    case "$(ppd2ui "$(get_ppd)")" in
      eco)      set_ui balanced ;;
      balanced) set_ui performance ;;
      *)        set_ui eco ;;
    esac ;;
  *) echo "usage: $0 {get|eco|balanced|performance|cycle}" >&2; exit 2 ;;
esac
