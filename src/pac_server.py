#!/usr/bin/env python3
"""Serve a PAC file locally with the MIME type Windows expects.

Product ("engine") server. Supports:
  * GET  /proxy.pac   -> the PAC payload with the MIME type Windows expects
  * GET  /healthz     -> JSON {status, pac_file, pid} for liveness/identity checks
  * --pid-file        -> write our process id on start; removed again on a clean
                         stop (Ctrl+C / KeyboardInterrupt). A stale pid file left
                         by a hard kill is EXPECTED and safe: management tooling
                         always cross-checks the real port listener (see
                         scripts/Apply-PacConfig.ps1), so it never trusts it.

Defaults point at the live C:\\proxy workflow so it can be launched with no
arguments (scheduled task / .bat). Optional CLI overrides exist for tests and
for the product pipeline (Apply-PacConfig.ps1 / Start-PacServer.ps1).
"""

from __future__ import annotations

import argparse
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_PAC_FILE = r"C:\proxy\proxy.pac"
DEFAULT_PID_FILE = r"C:\proxy\pac-server.pid"


def create_handler(pac_file: Path):
    class PacHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - HTTP handler API requires this name.
            if self.path == "/healthz":
                body = json.dumps(
                    {"status": "ok", "pac_file": str(pac_file), "pid": os.getpid()}
                ).encode()
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if self.path != "/proxy.pac":
                self.send_error(HTTPStatus.NOT_FOUND, "Use /proxy.pac or /healthz")
                return

            try:
                body = pac_file.read_bytes()
            except FileNotFoundError:
                self.send_error(HTTPStatus.NOT_FOUND, f"PAC file not found: {pac_file}")
                return

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/x-ns-proxy-autoconfig")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            # Keep background operation quiet. Start-PacServer.ps1 redirects logs separately.
            return

    return PacHandler


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve a PAC file on localhost.")
    parser.add_argument("--pac-file", type=Path, default=DEFAULT_PAC_FILE)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", default=DEFAULT_PORT, type=int)
    parser.add_argument(
        "--pid-file",
        type=Path,
        default=DEFAULT_PID_FILE,
        help="Write this process's pid here on start; remove on clean stop.",
    )
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), create_handler(args.pac_file))
    server.daemon_threads = True
    # Match the live serve_pac.py behaviour: restart never hits "port busy".
    server.allow_reuse_address = True

    if args.pid_file is not None:
        # Fresh machines may not have the runtime directory yet; create it so a
        # logon autostart can start before the PAC has ever been generated.
        if parent := args.pid_file.parent:
            parent.mkdir(parents=True, exist_ok=True)
        args.pid_file.write_text(str(os.getpid()))
    try:
        server.serve_forever()
    finally:
        # Runs on KeyboardInterrupt (Ctrl+C) / graceful exits; a hard kill skips
        # this, which is fine because callers never trust the pid file alone.
        if args.pid_file is not None:
            args.pid_file.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
