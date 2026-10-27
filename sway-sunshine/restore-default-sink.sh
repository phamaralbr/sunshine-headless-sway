#!/bin/bash
# Restores the host's default audio sink after Sunshine changes it.
# Sunshine sets audio_sink as the system default when a client connects.
# Uses systemd-run to spawn a detached watcher that survives prep-cmd cleanup.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Get the current default sink ID from wpctl
# Format: " │  *   44. Komplete Audio 2 ..."
SINK_ID=$(wpctl status 2>/dev/null | grep -A20 'Sinks:' | grep '\*' | head -1 | grep -oE '[0-9]+' | head -1)

if [ -z "$SINK_ID" ]; then
    exit 0
fi

# Clean up any previous instance
systemctl --user stop sunshine-sink-restore 2>/dev/null
systemctl --user reset-failed sunshine-sink-restore 2>/dev/null

# Launch a detached watcher via systemd-run (survives prep-cmd cleanup)
systemd-run --user --no-block --unit=sunshine-sink-restore \
    bash -c 'for i in $(seq 1 30); do sleep 1; CUR=$(wpctl status 2>/dev/null | grep -A20 "Sinks:" | grep "\*" | head -1 | grep -oE "[0-9]+" | head -1); if [ "$CUR" != "'"$SINK_ID"'" ] && [ -n "$CUR" ]; then wpctl set-default '"$SINK_ID"'; exit 0; fi; done'

# Keep Sunshine's capture on its own sink's monitor
systemctl --user stop sunshine-capture-fix 2>/dev/null
systemctl --user reset-failed sunshine-capture-fix 2>/dev/null
FIX_CAPTURE="$SCRIPT_DIR/fix-capture.sh"
if [ ! -f "$FIX_CAPTURE" ]; then
    FIX_CAPTURE="$HOME/.config/sway-sunshine/fix-capture.sh"
fi
systemd-run --user --no-block --unit=sunshine-capture-fix "$FIX_CAPTURE"
