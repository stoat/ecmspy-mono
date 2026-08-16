#!/usr/bin/env python3
"""Bridges the bike's USB-serial adapter to a local TCP port.

Runs on the host (not in Docker — Docker Desktop on Mac/Windows can't see
host USB devices) and replaces the previous platform-specific `socat`/
`ser2net` setup with one script that works the same way on Mac, Windows,
and Linux: it finds the adapter automatically and exposes it on TCP for
the ecmspy-container to connect to (SERIAL_HOST:SERIAL_PORT, default
host.docker.internal:2000).
"""

import argparse
import socket
import sys
import threading

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    import os
    sys.exit(
        "The 'pyserial' package is required.\n"
        "Install it by running this exact command:\n\n"
        f"    {sys.executable} -m pip install -r requirements.txt\n\n"
        "(run it from inside the ecmspy-container folder, so it can find "
        f"requirements.txt in {os.getcwd()})"
    )


def find_port(explicit_device=None):
    if explicit_device:
        return explicit_device

    ports = list(serial.tools.list_ports.comports())
    if not ports:
        sys.exit(
            "No serial ports found. Plug in the bike's USB diagnostic cable "
            "and try again (or pass --port to specify one manually)."
        )
    if len(ports) == 1:
        port = ports[0]
        print(f"Found: {port.device} ({port.manufacturer or port.description})")
        return port.device

    print("Multiple serial ports found:")
    for i, port in enumerate(ports, 1):
        print(f"  {i}. {port.device} ({port.manufacturer or port.description})")
    while True:
        choice = input(f"Select a port [1-{len(ports)}]: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(ports):
            return ports[int(choice) - 1].device
        print("Invalid choice.")


def pump_serial_to_socket(ser, conn, stop_event):
    try:
        while not stop_event.is_set():
            data = ser.read(ser.in_waiting or 1)
            if data:
                conn.sendall(data)
    except (OSError, serial.SerialException):
        pass
    finally:
        stop_event.set()


def pump_socket_to_serial(ser, conn, stop_event):
    conn.settimeout(0.5)
    try:
        while not stop_event.is_set():
            try:
                data = conn.recv(4096)
            except socket.timeout:
                continue
            if not data:
                break
            ser.write(data)
    except (OSError, serial.SerialException):
        pass
    finally:
        stop_event.set()


def handle_connection(ser, conn, addr):
    print(f"Client connected from {addr[0]}:{addr[1]}")
    stop_event = threading.Event()
    threads = [
        threading.Thread(target=pump_serial_to_socket, args=(ser, conn, stop_event), daemon=True),
        threading.Thread(target=pump_socket_to_serial, args=(ser, conn, stop_event), daemon=True),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    conn.close()
    print("Client disconnected; waiting for next connection...")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial device to use (skips auto-detection)")
    parser.add_argument(
        "--baud", type=int, default=9600,
        help="Baud rate (default: 9600, matches Buell Stock ECMs; use 19200 for Factory Race ECMs)",
    )
    parser.add_argument("--bind", default="127.0.0.1", help="Address to listen on (default: 127.0.0.1)")
    parser.add_argument("--tcp-port", type=int, default=2000, help="TCP port to listen on (default: 2000)")
    args = parser.parse_args()

    device = find_port(args.port)

    try:
        ser = serial.Serial(
            device,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            rtscts=False,
            dsrdtr=False,
            timeout=0.5,
        )
    except serial.SerialException as e:
        sys.exit(f"Couldn't open {device}: {e}")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.bind, args.tcp_port))
    server.listen(1)
    server.settimeout(1.0)

    print(f"Bridging to TCP :{args.tcp_port} ... (Ctrl+C to stop)")

    try:
        while True:
            try:
                conn, addr = server.accept()
            except socket.timeout:
                continue
            handle_connection(ser, conn, addr)
    except KeyboardInterrupt:
        print("\nStopping.")
    finally:
        server.close()
        ser.close()


if __name__ == "__main__":
    main()
