#!/bin/bash
# Launches Heroic inside the headless Sway session

SWAYSOCK="${SWAYSOCK:-/run/user/$(id -u)/sway-sunshine.sock}"
export SWAYSOCK

# Ensure audio routes to Sunshine's virtual sink
export PULSE_SINK="sink-sunshine-stereo"

# Close any residual instances
pkill -x heroic 2>/dev/null
pkill -f "heroic/resources" 2>/dev/null

# Launch Heroic inside the Sway compositor
swaymsg exec "PULSE_SINK=sink-sunshine-stereo heroic --fullscreen"
