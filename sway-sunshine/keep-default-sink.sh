#!/bin/bash
# Enforces host default audio sink against Sunshine hijacking.
# Subscribes to PulseAudio server events and restores the host sink whenever it changes.
#
# Usage: keep-default-sink.sh [target_sink_name]
# If no target sink is specified, it auto-detects the currently active non-Sunshine sink.

TARGET_SINK="$1"

if [ -z "$TARGET_SINK" ]; then
    # Pick the current default sink if it's not a sunshine sink
    CUR_DEFAULT="$(pactl get-default-sink 2>/dev/null)"
    if [[ "$CUR_DEFAULT" != *"sink-sunshine"* ]] && [ -n "$CUR_DEFAULT" ]; then
        TARGET_SINK="$CUR_DEFAULT"
    else
        # Fall back to the first non-Sunshine sink
        TARGET_SINK="$(pactl list short sinks 2>/dev/null | awk '$2 !~ /sink-sunshine/ {print $2; exit}')"
    fi
fi

if [ -z "$TARGET_SINK" ]; then
    echo "Error: No suitable host default sink found to protect." >&2
    exit 1
fi

echo "Enforcing host default sink: $TARGET_SINK"

fix_sink() {
    local current
    current="$(pactl get-default-sink 2>/dev/null)"
    if [ "$current" != "$TARGET_SINK" ]; then
        pactl set-default-sink "$TARGET_SINK" 2>/dev/null
    fi
}

fix_sink
pactl subscribe 2>/dev/null | grep --line-buffered "on server" | while read -r _; do
    fix_sink
done
