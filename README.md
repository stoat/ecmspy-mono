# ecmspy-container

A Docker wrapper for running **EcmSpy for Mono** — a Windows/Mono diagnostic
tool for Buell motorcycle ECMs (engine control modules) — headlessly in a
container, with the GUI exposed in a browser over noVNC and the serial
connection to the bike bridged in over TCP.

This repo contains only the *packaging*: a Dockerfile, a compose file, and a
startup script. It does **not** contain EcmSpy itself — see
[Legal notice](#legal-notice) below.

## How it works

```
┌─────────────────────────── container ───────────────────────────┐
│                                                                    │
│  Xvfb (virtual display) ── Fluxbox (window manager)                │
│         │                                                          │
│         └── ecmspy_mono.exe (via mono)                             │
│                                                                    │
│  x11vnc ── websockify/noVNC ── :6080 (browser access)               │
│                                                                    │
│  socat: PTY ⇄ TCP  ──────────────────────────────────────┐         │
│         (exposed to EcmSpy as a local /dev/ttyUSB0-style  │        │
│          serial device)                                   │        │
└─────────────────────────────────────────────────────────┼────────┘
                                                             │
                                              SERIAL_HOST:SERIAL_PORT
                                        (a TCP-exposed serial connection
                                         to the bike's diagnostic cable,
                                         e.g. via ser2net on the host)
```

At build time, the image extracts EcmSpy from its official Inno Setup
installer using [`innoextract`](https://constexpr.org/innoextract/) — no
Wine required, and no EcmSpy binaries are ever committed to this repo.

At runtime, `start-ecmspy.sh`:
1. Starts a virtual X display (Xvfb) and a minimal window manager (Fluxbox).
2. Starts `x11vnc` and bridges it to a browser-accessible noVNC endpoint on
   port `6080`.
3. Starts a `socat` bridge that connects out to `SERIAL_HOST:SERIAL_PORT`
   over TCP and exposes it inside the container as a PTY, so EcmSpy can talk
   to it like a normal serial device.
4. Launches `ecmspy_mono.exe` under Mono.

## Legal notice

**EcmSpy is proprietary, third-party software and is not included in this
repository.** Its EULA (bundled with the installer) grants a personal,
non-commercial, single-computer license and explicitly prohibits copying,
publishing, or redistributing the software. This repo only ever operates on
a copy of the installer *you* provide locally and legally own — it is never
committed to git or baked into a published image.

You are responsible for obtaining your own legitimate copy of the "EcmSpy
for Mono" installer and complying with its license.

## Prerequisites

- Docker and Docker Compose
- Your own legally obtained `EcmSpy_Mono_2.0-Setup.exe` installer
- A way to expose the diagnostic cable's serial port over TCP, reachable
  from the container (e.g. a USB-to-serial adapter plugged into the Docker
  host, shared via [`ser2net`](https://github.com/cminyard/ser2net) or
  similar). By default the container looks for this at
  `host.docker.internal:2000`.

## Setup

1. Place your installer at `installer/EcmSpy_Mono_2.0-Setup.exe` (this path
   is gitignored and stays local to your machine).
2. Build and start the container:

   ```sh
   docker compose up --build
   ```
3. Open EcmSpy in your browser:

   ```
   http://localhost:6080/vnc.html
   ```

## Configuration

Set via environment variables in `compose.yaml`:

| Variable      | Default                 | Description                                   |
|---------------|--------------------------|------------------------------------------------|
| `SERIAL_HOST` | `host.docker.internal`  | Host/IP of the TCP-exposed serial connection   |
| `SERIAL_PORT` | `2000`                  | Port of the TCP-exposed serial connection      |
| `NOVNC_PORT`  | `6080`                  | Port to expose the noVNC web UI on             |

Volumes:

- `./data` → `/home/ecmspy/data` — mount point where the bridged serial
  device is linked (`data/ttyUSB0`)
- `ecmspy-logs` (named volume) → `/home/ecmspy/ecmspy/applog` — EcmSpy's
  application logs, persisted across container restarts

## Development / testing

`Dockerfile.test` builds a minimal, non-VNC image (headless Xvfb only) for
smoke-testing that EcmSpy launches correctly under Mono:

```sh
docker build -f Dockerfile.test -t ecmspy-test .
docker run --rm ecmspy-test
```

## License

The packaging in this repository (`Dockerfile`, `Dockerfile.test`,
`compose.yaml`, `start-ecmspy.sh`) is licensed under the [MIT
License](LICENSE). EcmSpy itself is proprietary software under its own
license and is not covered by this repo's license.
