# Headless Sway + Sunshine Game Streaming

> **DISCLAIMER**: This is provided as-is with absolutely no warranty or guarantee. Use at your own risk.

![Architecture Diagram](diagram.svg)

Stream games from a headless Sway session using [Sunshine](https://github.com/LizardByte/Sunshine) and [Moonlight](https://moonlight-stream.org/), without disrupting your main desktop session.

This setup runs a separate headless Wayland compositor (Sway) dedicated to game streaming. Your primary desktop (GNOME, KDE, etc.) continues running normally — audio, display, and input are fully isolated.

## Why headless?

- Stream games without taking over your main display or moving your mouse cursor
- True multi-seat input isolation: host input stays on host, Moonlight input stays in stream
- Dynamic resolution matching — the headless output adapts to your Moonlight client
- Game audio routes only to the stream; host audio (speakers/DAC) is unaffected
- Supports Steam (Big Picture, individual games) and Heroic Games Launcher (Epic, GOG, Amazon)
- Minimal overhead when idle (~420MB RAM, negligible CPU)

## Requirements

- **OS**: Linux with systemd user services (Arch Linux / CachyOS, Ubuntu/Debian, Fedora)
- **Packages**: `sway`, `swaybg`, `pipewire`, `wireplumber`, `xdg-desktop-portal-wlr`, `gcc`
- **User Groups**: User must be a member of the `input` group
- **Sunshine**: [LizardByte Sunshine](https://github.com/LizardByte/Sunshine/releases)
- **Client**: [Moonlight](https://moonlight-stream.org/) on any device

## Quick install

```bash
git clone https://github.com/daaaaan/sunshine-headless-sway.git
cd sunshine-headless-sway
./install.sh
```

The install script will:
- Install missing dependencies (`sway`, `swaybg`, `xdg-desktop-portal-wlr`, `gcc`)
- Ensure user membership in the `input` group
- Compile the `libseat-seat1.so` shim into `~/.local/lib/`
- Create a capability-free Sway copy at `~/.local/bin/sway-seat1`
- Install the `70-sunshine-seat.rules` udev rule for true seat1 input isolation
- Install and configure Sway and Sunshine launch/stop scripts (Steam & Heroic)
- Install and enable systemd user services (`sway-sunshine.service`, `sunshine-headless.service`)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Main Desktop (GNOME / KDE)              seat0       wayland-0  │
│  ├─ Normal apps, browser, work                                  │
│  ├─ Host physical input devices (keyboard, mouse)               │
│  └─ Audio → host speakers / USB DAC                             │
├─────────────────────────────────────────────────────────────────┤
│  Headless Sway                           seat1       wayland-1  │
│  ├─ Steam & Heroic games launched via Sunshine                  │
│  ├─ Moonlight virtual inputs (libvirtualhid / seat1)            │
│  ├─ Audio → sink-sunshine-stereo → Moonlight stream             │
│  └─ Video → wlr-screencopy → Hardware Encoder → Moonlight       │
└─────────────────────────────────────────────────────────────────┘
```

Two systemd user services manage the headless stack:

1. **`sway-sunshine.service`** — runs a headless Sway compositor configured for `seat1`
2. **`sunshine-headless.service`** — runs Sunshine connected to the headless Sway display

---

## How it works

### 1. Input isolation (`seat1` + libseat shim)

Older approaches tried setting `mutter-device-ignore` or stripping `ID_INPUT` tags on `seat0`. These fail on modern desktop environments: both `gnome-shell` (Mutter) and `sway` hold virtual input devices open directly on `seat0`. Furthermore, modern Sunshine creates devices named `libvirtualhid ...` with vendor `1209` (reported as `4617` by Sway) instead of legacy `beef:dead`.

The solution is true multi-seat isolation:

1. **Udev Rule (`udev/70-sunshine-seat.rules`)**:
   Matches Sunshine virtual devices (`libvirtualhid*`, vendor `1209`, and legacy `beef:dead`) and assigns them to `ID_SEAT="seat1"`:
   ```udev
   SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="libvirtualhid*", ENV{ID_SEAT}="seat1"
   SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="1209", ENV{ID_SEAT}="seat1"
   SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="beef", ATTRS{id/product}=="dead", ENV{ID_SEAT}="seat1"
   ```
   Because Mutter/KWin listen only on `seat0`, they completely ignore these virtual devices.

2. **Libseat Shim (`libseat-shim/seat1.c`)**:
   wlroots uses `libseat` to discover its seat. With the `noop` backend (`LIBSEAT_BACKEND=noop`), `libseat_seat_name()` always returns `"seat0"`. Moving devices to `seat1` would therefore hide them from Sway as well.
   We inject a tiny preload shim (`libseat-seat1.so`) that overrides `libseat_seat_name` to return `"seat1"`, allowing headless Sway to bind to `seat1`.

3. **Capability-Free Sway Binary (`sway-seat1`)**:
   On distributions like Arch Linux, `/usr/bin/sway` carries a file capability (`cap_sys_nice=ep`). Linux's dynamic linker (`ld.so`) automatically strips `LD_PRELOAD` from any binary with file capabilities or setuid bits (such as `sg`).
   `sway-sunshine.service` copies `/usr/bin/sway` to `~/.local/bin/sway-seat1` via `ExecStartPre`, stripping capabilities so `LD_PRELOAD=~/.local/lib/libseat-seat1.so` is loaded.

4. **Sway Input Configuration (`sway-sunshine/config`)**:
   Headless Sway disables all physical inputs (`input * events disabled`) and only enables virtual Sunshine devices:
   ```
   input * events disabled
   input "4617:3:libvirtualhid_Mouse" events enabled
   input "4617:3:libvirtualhid_Mouse_(Absolute)" events enabled
   input "4617:2:libvirtualhid_Keyboard" events enabled
   input "4617:4:libvirtualhid_Touchscreen" events enabled
   input "4617:6:libvirtualhid_Pen_Tablet" events enabled
   input "4617:3:libvirtualhid_Mouse" accel_profile flat
   input "4617:3:libvirtualhid_Mouse_(Absolute)" accel_profile flat
   ```

---

### 2. Audio isolation (Capture pinning & default sink protection)

To ensure desktop audio (e.g. YouTube, Spotify) stays on your host DAC/speakers while game audio goes only into the stream:

1. **Virtual Audio Sink**:
   Sway services and games run with `PULSE_SINK=sink-sunshine-stereo`.
   Sunshine is configured with `audio_sink = sink-sunshine-stereo` and `capture = wlr`.

2. **Default Sink Restoration (`restore-default-sink.sh`)**:
   When Moonlight connects, Sunshine temporarily sets `sink-sunshine-stereo` as the system default sink.
   `restore-default-sink.sh` runs as a prep command: it records the host's actual default sink (e.g., USB DAC) and spawns a background watcher (`sunshine-sink-restore`) via `systemd-run --user` that restores `wpctl set-default` once Sunshine switches it.

3. **Capture Stream Pinning (`fix-capture.sh`)**:
   Once the host default sink is switched back to the DAC, an unpinned Sunshine audio capture stream would follow the default and capture the host DAC monitor — leaking desktop audio into the stream.
   `fix-capture.sh` (spawned by `restore-default-sink.sh` as `sunshine-capture-fix`) locates Sunshine's `source-output` and explicitly pins it to `sink-sunshine-stereo.monitor`.

4. **Optional Sink Enforcer (`keep-default-sink.sh`)**:
   A standalone utility that listens to PulseAudio server events and enforces the host's physical default sink.

> [!NOTE]
> Modern Sunshine releases create virtual sinks dynamically. If both PipeWire's `sunshine-null-sink.conf` drop-in and Sunshine create sinks with identical names (`sink-sunshine-stereo`), sink lookups can become ambiguous. If you see duplicate sinks in `pactl list short sinks`, remove `~/.config/pipewire/pipewire.conf.d/sunshine-null-sink.conf`.

---

### 3. Application launchers (Steam & Heroic)

Scripts located in `~/.config/sway-sunshine/` handle application lifecycle:

#### Heroic Games Launcher
- **`start-heroic.sh`**: Sets `SWAYSOCK` and `PULSE_SINK`, kills any lingering instances, and launches `heroic --fullscreen` inside Sway.
- **`stop-heroic.sh`**: Cleanly sends `SIGTERM` to `heroic` and `wineserver`, waits up to 5 seconds, and closes any remaining Sway windows.

#### Steam
- **`start-steam-game.sh`**: Shuts down any existing Steam desktop instance, cleans IPC locks (`~/.steam/steam.pid`), and launches Steam in Sway using `steam -bigpicture` or `steam -applaunch <APP_ID>`.
- **`stop-steam-game.sh`**: Initiates `steam -shutdown` (allowing Steam Cloud sync), terminates lingering Wine/game processes, and closes dangling Sway windows.

#### Configuration in `apps.json`
Entries in `~/.config/sunshine/apps.json`:

```json
{
  "name": "Heroic Games Launcher",
  "detached": [
    "/home/YOUR_USER/.config/sway-sunshine/start-heroic.sh"
  ],
  "image-path": "heroic.png",
  "prep-cmd": [
    {
      "do": "/home/YOUR_USER/.config/sway-sunshine/restore-default-sink.sh",
      "undo": ""
    },
    {
      "do": "/home/YOUR_USER/.config/sway-sunshine/set-resolution.sh",
      "undo": "/home/YOUR_USER/.config/sway-sunshine/stop-heroic.sh"
    }
  ]
}
```

---

## Verification & Troubleshooting

### Input isolation verification
1. Check that Sunshine devices are assigned to `seat1`:
   ```bash
   udevadm info /dev/input/eventX | grep ID_SEAT
   # Should output: ID_SEAT=seat1
   ```
2. Verify only Sway holds the virtual input devices:
   ```bash
   sudo fuser -v /dev/input/eventX
   # Should list 'sway-seat1' (or 'sway'), and NOT 'gnome-shell' or 'kwin'
   ```
3. Verify the shim is loaded into the Sway process:
   ```bash
   grep seat1 /proc/$(systemctl --user show sway-sunshine -p MainPID --value)/maps
   # Should display: ... ~/.local/lib/libseat-seat1.so
   ```
4. Verify Sway input devices:
   ```bash
   SWAYSOCK=/run/user/$(id -u)/sway-sunshine.sock swaymsg -t get_inputs | grep identifier
   ```

### Audio isolation verification
With Moonlight connected and playing sound in both host and stream:
1. Verify host default sink remains on your DAC:
   ```bash
   pactl get-default-sink
   ```
2. Verify host apps output to your DAC while games output to `sink-sunshine-stereo`:
   ```bash
   pactl list short sink-inputs
   ```
3. Verify Sunshine's capture stream is pinned to `sink-sunshine-stereo.monitor`:
   ```bash
   pactl list short source-outputs
   ```

---

## File Structure

```
udev/
└── 70-sunshine-seat.rules       # Assigns Sunshine virtual inputs to seat1

libseat-shim/
├── seat1.c                      # Overrides libseat_seat_name to "seat1"
└── Makefile                     # Builds libseat-seat1.so

pipewire/
└── sunshine-null-sink.conf      # Optional persistent null sink

sway-sunshine/
├── config                       # Headless Sway compositor configuration
├── set-resolution.sh            # Dynamic resolution matching on connect
├── reset-resolution.sh          # Reverts resolution on disconnect
├── restore-default-sink.sh      # Restores host default sink
├── fix-capture.sh               # Pins Sunshine audio capture to stream sink
├── keep-default-sink.sh         # Persistent host sink enforcer
├── start-heroic.sh              # Heroic Games Launcher startup
├── stop-heroic.sh               # Heroic / Wine cleanup
├── start-steam-game.sh          # Steam startup (Big Picture or app ID)
└── stop-steam-game.sh           # Steam / Wine cleanup

sunshine/
├── sunshine.conf                # Sunshine server configuration
└── apps.json                    # Moonlight application definitions

systemd/
├── sway-sunshine.service        # Headless Sway systemd service (seat1)
└── sunshine-headless.service    # Headless Sunshine systemd service
```

## License

MIT — do whatever you want with it, but don't blame us if something breaks.
