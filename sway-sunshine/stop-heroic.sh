#!/bin/bash
# Cleanly shuts down Heroic, Wine/Proton games, and dangling windows

SWAYSOCK="${SWAYSOCK:-/run/user/$(id -u)/sway-sunshine.sock}"
export SWAYSOCK

# 1. Ask Heroic and Wine processes to close gently
pkill -TERM -x heroic 2>/dev/null
pkill -TERM -f "wineserver" 2>/dev/null

# Wait up to 5 seconds for clean exit
for _ in $(seq 1 5); do
    pgrep -x heroic > /dev/null 2>&1 || break
    sleep 1
done

# 2. Clean up any stuck windows in Sway
if [ -S "$SWAYSOCK" ]; then
    swaymsg '[app_id=".*"] kill' 2>/dev/null || true
    swaymsg '[class=".*"] kill' 2>/dev/null || true
fi

