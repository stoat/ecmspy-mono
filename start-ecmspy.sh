#!/usr/bin/env bash

set -u

export DISPLAY="${DISPLAY:-:1}"
export HOME="${HOME:-/home/ecmspy}"

NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"

SERIAL_HOST="${SERIAL_HOST:-host.docker.internal}"
SERIAL_PORT="${SERIAL_PORT:-2000}"
SERIAL_DEVICE="${SERIAL_DEVICE:-/tmp/ttyUSB0}"

ECMSPY_DIR="/home/ecmspy/ecmspy"
ECMSPY_EXE="${ECMSPY_DIR}/ecmspy_mono.exe"

cleanup() {
    trap - EXIT INT TERM
    jobs -p | xargs --no-run-if-empty kill 2>/dev/null || true
}

trap cleanup EXIT INT TERM

mkdir -p \
    "${ECMSPY_DIR}/applog" \
    /home/ecmspy/data

echo "Starting virtual display on ${DISPLAY}..."

# A container restart (vs. recreate) reuses the writable layer, so a lock
# file from a prior run's Xvfb can be left behind even though nothing is
# actually using the display anymore.
rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}"

Xvfb "$DISPLAY" \
    -screen 0 1280x800x24 \
    -nolisten tcp \
    >/tmp/xvfb.log 2>&1 &

XVFB_PID=$!

sleep 2

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "Xvfb failed:"
    cat /tmp/xvfb.log
    exit 1
fi

echo "Starting Fluxbox..."

fluxbox \
    >/tmp/fluxbox.log 2>&1 &

echo "Starting VNC server..."

x11vnc \
    -display "$DISPLAY" \
    -forever \
    -shared \
    -nopw \
    -rfbport "$VNC_PORT" \
    >/tmp/x11vnc.log 2>&1 &

echo "Starting noVNC on port ${NOVNC_PORT}..."

websockify \
    --web=/usr/share/novnc \
    "$NOVNC_PORT" \
    "localhost:${VNC_PORT}" \
    >/tmp/novnc.log 2>&1 &

echo "Starting serial bridge to ${SERIAL_HOST}:${SERIAL_PORT}..."

(
    while true; do
        rm -f "$SERIAL_DEVICE"

        socat \
            "PTY,link=${SERIAL_DEVICE},raw,echo=0,mode=666" \
            "TCP:${SERIAL_HOST}:${SERIAL_PORT},connect-timeout=10"

        echo "$(date): serial bridge disconnected; retrying in 3 seconds"
        sleep 3
    done
) >/tmp/socat.log 2>&1 &

# ECMSpy/Mono can use this Linux serial-device path.
# The link may not exist until socat connects successfully.
ln -sfn "$SERIAL_DEVICE" /home/ecmspy/data/ttyUSB0

if [[ ! -f "$ECMSPY_EXE" ]]; then
    echo "ECMSpy executable not found:"
    echo "$ECMSPY_EXE"
    exit 1
fi

echo "Starting ECMSpy..."

cd "$ECMSPY_DIR"

mono "$ECMSPY_EXE" \
    >/tmp/ecmspy.log 2>&1 &

ECMSPY_PID=$!

echo
echo "Open ECMSpy at:"
echo "http://localhost:${NOVNC_PORT}/vnc.html"
echo

# Keep the container alive as long as the virtual display is running.
wait "$XVFB_PID"