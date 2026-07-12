#!/usr/bin/env python3
"""Serve a PAC file locally with the MIME type Windows expects."""

from __future__ import annotations

import argparse
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def create_handler(pac_file: Path):
    class PacHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - HTTP handler API requires this name.
            if self.path == "/healthz":
                body = json.dumps({"status": "ok", "pac_file": str(pac_file)}).encode()
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
    parser.add_argument("--pac-file", required=True, type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), create_handler(args.pac_file.resolve()))
    server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
