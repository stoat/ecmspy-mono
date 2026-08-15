#!/usr/bin/env bash

set -eu

# Mono's SerialPort.GetPortNames() only scans /dev for tty*-prefixed names,
# so the bridged serial device needs a symlink there for EcmSpy to see it
# as a selectable port. /dev is a fresh mount on every container start (so
# this can't be baked in at build time), and the ecmspy user has no write
# access to /dev, so this runs once as root before dropping privileges.
SERIAL_DEVICE="${SERIAL_DEVICE:-/tmp/ttyUSB0}"
ln -sf "$SERIAL_DEVICE" /dev/ttyUSB0

exec gosu ecmspy /usr/local/bin/start-ecmspy
