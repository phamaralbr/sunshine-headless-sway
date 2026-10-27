#!/bin/bash
set -euo pipefail

# Headless Sway + Sunshine Game Streaming Installer
# https://github.com/daaaaan/sunshine-headless-sway

SWAY_CONFIG_DIR="$HOME/.config/sway-sunshine"
SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Headless Sway + Sunshine Installer ==="
echo ""

# Detect package manager
install_pkg() {
    if command -v pacman &>/dev/null; then
        sudo pacman -S --needed --noconfirm "$@"
    elif command -v apt &>/dev/null; then
        sudo apt install -y "$@"
    else
        echo "Error: No supported package manager found (pacman or apt)"
        exit 1
    fi
}

is_pkg_installed() {
    if command -v pacman &>/dev/null; then
        pacman -Qi "$1" &>/dev/null
    elif command -v dpkg &>/dev/null; then
        dpkg -s "$1" &>/dev/null 2>&1
    else
        return 1
    fi
}

# Install dependencies
for cmd in sway swaybg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing sway and swaybg..."
        install_pkg sway swaybg
        break
    fi
done

if ! is_pkg_installed xdg-desktop-portal-wlr; then
    echo "Installing xdg-desktop-portal-wlr..."
    install_pkg xdg-desktop-portal-wlr
fi

if ! command -v gcc &>/dev/null; then
    echo "Installing gcc (needed for libseat shim)..."
    if command -v pacman &>/dev/null; then
        install_pkg gcc
    elif command -v apt &>/dev/null; then
        install_pkg build-essential
    fi
fi

# Ensure user is in input group for virtual device access
if ! groups "$USER" 2>/dev/null | grep -q '\binput\b'; then
    echo "Adding $USER to the 'input' group for input access..."
    sudo usermod -aG input "$USER"
    echo "Note: If this is the first time adding $USER to 'input', a re-login may be needed."
fi

# Check for Sunshine
SUNSHINE_PATH=""
if command -v sunshine &>/dev/null; then
    SUNSHINE_PATH="$(command -v sunshine)"
elif [ -f "$HOME/Apps/sunshine.AppImage" ]; then
    SUNSHINE_PATH="$HOME/Apps/sunshine.AppImage"
else
    echo ""
    echo "Sunshine not found. Please install it from:"
    echo "  https://github.com/LizardByte/Sunshine/releases"
    echo ""
    read -rp "Enter the path to your Sunshine binary/AppImage: " SUNSHINE_PATH
    if [ ! -f "$SUNSHINE_PATH" ]; then
        echo "Error: $SUNSHINE_PATH not found"
        exit 1
    fi
fi

echo "Using Sunshine at: $SUNSHINE_PATH"

# Detect Wayland display for the headless session
MAIN_WAYLAND=$(ls /run/user/$(id -u)/wayland-* 2>/dev/null | grep -v lock | sort | tail -1 | xargs basename)
if [ -z "$MAIN_WAYLAND" ] || [ "$MAIN_WAYLAND" = "wayland-0" ]; then
    HEADLESS_DISPLAY="wayland-1"
else
    HEADLESS_DISPLAY="wayland-$((${MAIN_WAYLAND##wayland-} + 1))"
fi
echo "Main display: ${MAIN_WAYLAND:-wayland-0}, headless will be: $HEADLESS_DISPLAY"

USER_ID=$(id -u)

echo ""
echo "Building libseat seat1 shim..."
mkdir -p "$HOME/.local/lib"
gcc -O2 -shared -fPIC -o "$HOME/.local/lib/libseat-seat1.so" "$SCRIPT_DIR/libseat-shim/seat1.c"
echo "  → Installed $HOME/.local/lib/libseat-seat1.so"

echo "Setting up capability-free sway binary..."
mkdir -p "$HOME/.local/bin"
SWAY_BIN="$(command -v sway || echo "/usr/bin/sway")"
cp -f "$SWAY_BIN" "$HOME/.local/bin/sway-seat1"
echo "  → Installed $HOME/.local/bin/sway-seat1"

echo "Installing udev rule for seat1 input isolation..."
sudo cp "$SCRIPT_DIR/udev/70-sunshine-seat.rules" "/etc/udev/rules.d/70-sunshine-seat.rules"
# Clean up obsolete rules
sudo rm -f /etc/udev/rules.d/85-sunshine-input-isolation*.rules 2>/dev/null || true
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input 2>/dev/null || true
echo "  → Installed /etc/udev/rules.d/70-sunshine-seat.rules"

echo ""
echo "Installing config files..."

# Sway config and scripts
mkdir -p "$SWAY_CONFIG_DIR"
cp "$SCRIPT_DIR/sway-sunshine/config" "$SWAY_CONFIG_DIR/config"

for script in set-resolution.sh reset-resolution.sh restore-default-sink.sh fix-capture.sh keep-default-sink.sh start-heroic.sh stop-heroic.sh start-steam-game.sh stop-steam-game.sh; do
    if [ -f "$SCRIPT_DIR/sway-sunshine/$script" ]; then
        cp "$SCRIPT_DIR/sway-sunshine/$script" "$SWAY_CONFIG_DIR/$script"
        chmod +x "$SWAY_CONFIG_DIR/$script"
    fi
done

# Sunshine config (only if not already configured)
mkdir -p "$SUNSHINE_CONFIG_DIR"
if [ ! -f "$SUNSHINE_CONFIG_DIR/sunshine.conf" ]; then
    cp "$SCRIPT_DIR/sunshine/sunshine.conf" "$SUNSHINE_CONFIG_DIR/sunshine.conf"
    echo "Created sunshine.conf"
elif ! grep -q "^audio_sink" "$SUNSHINE_CONFIG_DIR/sunshine.conf"; then
    if grep -q "^sink " "$SUNSHINE_CONFIG_DIR/sunshine.conf"; then
        sed -i 's/^sink = /audio_sink = /' "$SUNSHINE_CONFIG_DIR/sunshine.conf"
        echo "Migrated 'sink' to 'audio_sink' in existing sunshine.conf"
    else
        echo "audio_sink = sink-sunshine-stereo" >> "$SUNSHINE_CONFIG_DIR/sunshine.conf"
        echo "Added audio_sink to existing sunshine.conf"
    fi
    if ! grep -q "^capture" "$SUNSHINE_CONFIG_DIR/sunshine.conf"; then
        echo "capture = wlr" >> "$SUNSHINE_CONFIG_DIR/sunshine.conf"
        echo "Added capture = wlr to sunshine.conf"
    fi
else
    echo "sunshine.conf already configured, skipping"
fi

# Apps config (only if not already present)
if [ ! -f "$SUNSHINE_CONFIG_DIR/apps.json" ]; then
    sed -e "s|/home/YOUR_USER/|$HOME/|g" \
        -e "s|/run/user/1000/|/run/user/$USER_ID/|g" \
        "$SCRIPT_DIR/sunshine/apps.json" > "$SUNSHINE_CONFIG_DIR/apps.json"
    echo "Created apps.json"
else
    echo "apps.json already exists, skipping (see sunshine/apps.json for reference)"
fi

# Systemd services
mkdir -p "$SYSTEMD_DIR"
cp "$SCRIPT_DIR/systemd/sway-sunshine.service" "$SYSTEMD_DIR/sway-sunshine.service"

sed -e "s|WAYLAND_DISPLAY=wayland-1|WAYLAND_DISPLAY=$HEADLESS_DISPLAY|g" \
    -e "s|ExecStart=.*|ExecStart=$SUNSHINE_PATH $SUNSHINE_CONFIG_DIR/sunshine.conf|g" \
    "$SCRIPT_DIR/systemd/sunshine-headless.service" > "$SYSTEMD_DIR/sunshine-headless.service"

# Optional PipeWire persistent null sink
# Note: Newer Sunshine releases create virtual sinks automatically.
# If your setup experiences missing sink issues on cold boot, install:
#   cp pipewire/sunshine-null-sink.conf ~/.config/pipewire/pipewire.conf.d/
PIPEWIRE_DIR="$HOME/.config/pipewire/pipewire.conf.d"
if [ ! -f "$PIPEWIRE_DIR/sunshine-null-sink.conf" ]; then
    mkdir -p "$PIPEWIRE_DIR"
    cp "$SCRIPT_DIR/pipewire/sunshine-null-sink.conf" "$PIPEWIRE_DIR/sunshine-null-sink.conf"
    echo "Installed PipeWire persistent audio sink"
fi

echo "Installed systemd services"

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable sway-sunshine.service
systemctl --user enable sunshine-headless.service

echo ""
echo "=== Installation complete ==="
echo ""
echo "Input isolation: seat1 udev rule + libseat shim active"
echo "Audio isolation: sink restoration + capture pinning configured"
echo ""
echo "To start streaming now:"
echo "  systemctl --user start sway-sunshine.service"
echo ""
echo "To check status:"
echo "  systemctl --user status sway-sunshine sunshine-headless"
echo ""
echo "To configure games (Steam, Heroic), edit:"
echo "  $SUNSHINE_CONFIG_DIR/apps.json"
echo ""
echo "Pair with Moonlight at: https://$(hostname):47990"
echo ""

read -rp "Start the services now? [Y/n] " START
if [[ "${START:-Y}" =~ ^[Yy]?$ ]]; then
    systemctl --user start sway-sunshine.service
    echo "Services started. Open Moonlight to connect."
fi
