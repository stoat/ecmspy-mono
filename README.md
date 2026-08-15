# ecmspy-container

A Docker wrapper for running **EcmSpy for Mono** — a Windows/Mono diagnostic
tool for Buell motorcycle ECMs (engine control modules) — headlessly in a
container, with the GUI exposed in a browser over noVNC and the serial
connection to the bike bridged in over TCP.

This repo contains only the *packaging*: a Dockerfile, a compose file, and a
startup script. It does **not** contain EcmSpy itself — see
[Legal notice](#legal-notice) below.

## Quick start (no coding experience needed)

This section is for people who just want to plug in their bike and open
EcmSpy — it doesn't assume you know what Docker or a terminal is. If you get
stuck, the more technical [Setup](#setup) section below has the same steps
in short form.

**Before you start**, the computer with the bike's USB diagnostic cable
plugged into it needs to be sharing that cable over the network — step 3
below covers this for a Mac. If someone else already set this up for you
(e.g. via `ser2net` on a separate box), you can skip straight to step 4.

### 1. Install Docker Desktop

Docker Desktop is the one program that runs everything else for you.

1. Go to <https://www.docker.com/products/docker-desktop/> and download
   Docker Desktop for your computer (Mac or Windows).
2. Install it like any other application, then open it once. You should see
   a small whale icon appear — leave Docker Desktop running in the
   background whenever you use EcmSpy.

### 2. Download this project

1. Near the top of this page, click the green **Code** button, then
   **Download ZIP**.
2. Find the downloaded file (usually in your Downloads folder) and unzip it
   by double-clicking it. You'll end up with a folder named
   `ecmspy-container`.

### 3. Bridge the bike's USB cable to the network (Mac)

Skip this step if the cable is already being shared for you elsewhere.

1. Plug the bike's USB diagnostic cable into your Mac.
2. Open Terminal and run this to find the cable's device name:

   ```sh
   ls /dev/cu.usbserial-*
   ```

   You should see something like `/dev/cu.usbserial-AR0JV3ZE`. If you see
   nothing, unplug and replug the cable and try again.
3. If you don't already have `socat` installed, install
   [Homebrew](https://brew.sh) first, then run:

   ```sh
   brew install socat
   ```
4. Start the bridge, using the device name from step 2:

   ```sh
   socat -d -d TCP-LISTEN:2000,reuseaddr,fork,bind=127.0.0.1 \
     FILE:/dev/cu.usbserial-AR0JV3ZE,raw,echo=0
   ```

   Leave this Terminal window open and running the whole time you're using
   EcmSpy — closing it disconnects the bike. (`bind=127.0.0.1` keeps the
   connection local to this Mac only, which is all the container needs.)

### 4. Add your EcmSpy installer

1. Get your own legally purchased copy of `EcmSpy_Mono_2.0-Setup.exe` (see
   [Legal notice](#legal-notice) — this project doesn't include it).
2. Move that file into the `installer` folder inside `ecmspy-container`, so
   the path looks like `ecmspy-container/installer/EcmSpy_Mono_2.0-Setup.exe`.

### 5. Start EcmSpy

1. Open a **new** terminal window (leave the `socat` one from step 3
   running):
   - **Mac:** press **⌘ + Space**, type `Terminal`, press Return.
   - **Windows:** click Start, type `PowerShell`, press Enter.
2. Type `cd ` (with a trailing space), then drag the `ecmspy-container`
   folder from Finder/File Explorer into the terminal window and drop it —
   this fills in the folder's path for you. Press Return.
3. Type this and press Return:

   ```sh
   docker compose up --build
   ```
4. Wait. The first run downloads and builds everything, which can take
   several minutes — you'll see a lot of text scroll by, that's normal.
   It's ready when the scrolling slows down and you stop seeing new
   "building" messages.

### 6. Open EcmSpy in your browser

Go to:

```
http://localhost:6080/vnc.html
```

Click **Connect** if prompted. You should see the EcmSpy application
running, as if it were installed directly on your computer.

### Stopping and restarting

- To stop: go back to the terminal window running `docker compose` and
  press **Ctrl + C**. You can also stop the `socat` window if you're done
  with the bike.
- To use it again later: redo steps 3 (`socat`) and 5 (`docker compose up
  --build`) — steps 1, 2, and 4 only need to be done once.

### If something goes wrong

- **"docker: command not found"** — Docker Desktop isn't installed, or
  isn't finished starting up. Open the Docker Desktop app and wait for the
  whale icon to say it's running.
- **The browser page won't load** — make sure the terminal from step 5 is
  still open and running; closing it stops EcmSpy.
- **EcmSpy can't see the bike** — make sure the `socat` window from step 3
  is still open and running, and that the cable is plugged in. See
  [Configuration](#configuration) below for how to point this project at a
  different address, or ask whoever set up the cable bridge.

## How it works

```mermaid
flowchart TB
    subgraph host["Host machine"]
        bike["Bike ECM<br/>(USB diagnostic cable)"]
        socatHost["socat / ser2net<br/>TCP-LISTEN:SERIAL_PORT"]
        browser["Browser<br/>localhost:NOVNC_PORT/vnc.html"]
        bike -->|USB| socatHost
    end

    subgraph container["Docker container (ecmspy)"]
        socatC["socat<br/>PTY ⇄ TCP client"]
        pty["/tmp/ttyUSB0<br/>(virtual serial device)"]
        mono["mono<br/>ecmspy_mono.exe"]
        xvfb["Xvfb :1<br/>(virtual display)"]
        fluxbox["Fluxbox<br/>(window manager)"]
        x11vnc["x11vnc<br/>:5900"]
        novnc["websockify / noVNC<br/>:NOVNC_PORT"]

        socatC --> pty
        pty --> mono
        mono -->|renders on| xvfb
        fluxbox --- xvfb
        x11vnc -->|captures| xvfb
        novnc -->|proxies| x11vnc
    end

    socatHost <-->|"TCP SERIAL_HOST:SERIAL_PORT<br/>(default host.docker.internal:2000)"| socatC
    novnc <-->|WebSocket| browser
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

  On macOS, `socat` is a lighter-weight alternative to `ser2net` for
  sharing a single locally-attached USB adapter:

  ```sh
  socat -d -d TCP-LISTEN:2000,reuseaddr,fork,bind=127.0.0.1 \
    FILE:/dev/cu.usbserial-XXXXXXXX,raw,echo=0
  ```

  Replace `/dev/cu.usbserial-XXXXXXXX` with your adapter's actual device
  path (`ls /dev/cu.usbserial-*` to find it). `bind=127.0.0.1` restricts the
  bridge to the local machine — Docker Desktop's `host.docker.internal`
  reaches localhost-bound host ports, so the container can still connect.
  `fork` keeps `socat` running and accepting reconnects across container
  restarts.

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
