#!/usr/bin/env python3
"""Minimal stand-in for the Home Assistant Supervisor API.

Used by scripts/verify.sh to check that the add-on writes its generated
password back into its own options correctly -- specifically that it sends the
FULL option set, since Supervisor replaces options wholesale and a partial
write would silently discard everything else the user had configured.

    supervisor-stub.py <port> <capture-file>
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
CAPTURE = sys.argv[2]

# Deliberately more than one option, so a partial write is detectable.
EXISTING = {
    "log_level": "info",
    "workspace_root": "/share/paseo/workspace",
    "connection_mode": "local",
    "password": "",
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload, code=200):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/addons/self/info":
            self._send({"result": "ok", "data": {"options": EXISTING}})
        else:
            self._send({"result": "error"}, 404)

    def do_POST(self):
        if self.path == "/addons/self/options":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            with open(CAPTURE, "wb") as fh:
                fh.write(raw)
            self._send({"result": "ok"})
        else:
            self._send({"result": "error"}, 404)

    def log_message(self, *_args):
        pass  # quiet


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
