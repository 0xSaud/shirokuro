#!/usr/bin/env bash
# Start the Quickshell bar, and don't give up if the first try comes too early.
#
# At session start (especially on a compositor crash-restart) qs can exit
# immediately, before it writes any log, leaving a desktop with no bar and no
# clue why. Retry a few times, then keep it alive for the rest of the session.
set -uo pipefail

command -v qs >/dev/null 2>&1 || exit 0

# Don't stack a second bar on top of one that is already up.
pgrep -x qs >/dev/null 2>&1 && exit 0

for attempt in 1 2 3 4 5; do
    qs & pid=$!
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        wait "$pid"          # came up fine; block until it exits
        rc=$?
        [ "$rc" = 0 ] && exit 0   # clean exit (session ending) - stop here
    fi
    sleep 2
done
