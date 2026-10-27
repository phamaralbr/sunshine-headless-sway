#!/bin/bash
# Keeps Sunshine's capture stream on the Sunshine sink's monitor.
#
# When restore-default-sink.sh switches the system default sink back to
# the host DAC, unpinned capture streams can follow the default switch
# and capture desktop audio into the Moonlight stream. This script
# locates Sunshine's source-output and pins it to sink-sunshine-stereo.monitor.

for i in $(seq 1 120); do
    ID=$(pactl list source-outputs 2>/dev/null | awk '/^Source Output #/{id=substr($3,2)} /application.name = "sunshine"/{print id; exit}')
    if [ -n "$ID" ]; then
        pactl move-source-output "$ID" sink-sunshine-stereo.monitor 2>/dev/null
    fi
    sleep 1
done

