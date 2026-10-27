#!/bin/bash
# Shuts down Steam, games, and cleans the headless Sway session

SWAYSOCK="${SWAYSOCK:-/run/user/$(id -u)/sway-sunshine.sock}"
export SWAYSOCK

# 1. Ask Steam cleanly to exit (allows Steam Cloud sync to finish)
steam -shutdown 2>/dev/null

# 2. Wait up to 15s for Steam and any active games to exit
for i in $(seq 1 15); do
    pgrep -x steam > /dev/null 2>&1 || break
    sleep 1
done

# 3. If anything is still hanging, send SIGTERM (gentle exit request)
if pgrep -x steam > /dev/null 2>&1; then
    pkill -x steam 2>/dev/null
    pkill -f "wineserver" 2>/dev/null
    sleep 2
fi

# 4. Clean up IPC lock files
rm -f ~/.steam/steam.pid 2>/dev/null
rm -f /tmp/steam_singleton_* 2>/dev/null

# 5. Tell Sway to close any remaining windows (dialogs, stuck games, launchers)
if [ -S "$SWAYSOCK" ]; then
    swaymsg '[app_id=".*"] kill' 2>/dev/null || true
    swaymsg '[class=".*"] kill' 2>/dev/null || true
fi
