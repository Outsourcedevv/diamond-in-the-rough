"""Loopback-only updater fixtures. Uses synthetic credentials and harmless ZIP data."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

ASSET = "DIAMOND_IN_THE_ROUGH_Update.zip"
PAYLOAD = b"MZ HARMLESS UPDATER TEST DATA, NEVER EXECUTE\r\n" + bytes(range(256)) * 2048
build = {"schema": 1, "build": 2, "version": "0.3.2", "commit": "a" * 40}
stream = io.BytesIO()
with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_STORED) as archive:
    archive.writestr("DiamondInTheRough.exe", PAYLOAD)
    archive.writestr("build.json", json.dumps(build))
PACKAGE = stream.getvalue()
CORRUPT_PACKAGE = PACKAGE[:-1] + bytes([PACKAGE[-1] ^ 1])
SHA = hashlib.sha256(PACKAGE).hexdigest()
manifest = {
    **build,
    "asset": ASSET,
    "executable": "DiamondInTheRough.exe",
    "sha256": SHA,
    "size": len(PACKAGE),
}
AUDIT: list[dict] = []


def metadata(mode: str) -> bytes:
    value = dict(manifest)
    if mode == "bad-manifest":
        value["asset"] = "../evil.zip"
    elif mode == "downgrade":
        value["build"] = 1
        value["version"] = "0.3.1"
    return json.dumps(value).encode()


def release(mode: str) -> dict:
    return {
        "id": 1,
        "tag_name": "test-build",
        "draft": False,
        "prerelease": False,
        "body": "Synthetic updater verification release. No real binary is run.",
        "assets": [
            {"id": 1, "name": "latest.json", "state": "uploaded", "size": len(metadata(mode))},
            {
                "id": 2,
                "name": ASSET,
                "state": "uploaded",
                "size": len(PACKAGE),
                "digest": "sha256:" + ("0" * 64 if mode == "digest-mismatch" else SHA),
            },
        ],
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass  # Header values and credentials are never logged.

    def send_bytes(self, data: bytes, status: int = 200, content_type: str = "application/json", slow=False):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            if slow:
                for offset in range(0, len(data), 8192):
                    self.wfile.write(data[offset:offset + 8192])
                    self.wfile.flush()
                    time.sleep(0.02)
            else:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/control/reset":
            AUDIT.clear()
            self.send_bytes(b'{"reset":true}')
            return
        if path == "/control/audit":
            self.send_bytes(json.dumps({"requests": AUDIT}).encode())
            return
        AUDIT.append({"path": path, "authorized": bool(self.headers.get("Authorization"))})
        parts = path.strip("/").split("/")
        mode = parts[0] if parts else "good"
        if path == "/off-api/release":
            self.send_bytes(json.dumps(release("redirect-safe")).encode())
            return
        if path.endswith("/releases/latest"):
            if mode == "unauth":
                self.send_bytes(b'{"message":"Synthetic private repository requires access"}', 401)
            elif mode == "hostile-redirect":
                self.send_response(302)
                self.send_header("Location", "http://localhost:24788/leak")
                self.send_header("Content-Length", "0")
                self.end_headers()
            elif mode == "redirect-safe":
                self.send_response(302)
                self.send_header("Location", "http://127.0.0.1:24788/off-api/release")
                self.send_header("Content-Length", "0")
                self.end_headers()
            else:
                self.send_bytes(json.dumps(release(mode)).encode())
        elif path.endswith("/releases/assets/1"):
            self.send_bytes(metadata(mode), content_type="application/octet-stream")
        elif path.endswith("/releases/assets/2"):
            self.send_bytes(CORRUPT_PACKAGE if mode == "bad-hash" else PACKAGE, content_type="application/octet-stream", slow=True)
        else:
            self.send_bytes(b"{}", 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=24788)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Updater fixtures listening on loopback port {args.port}; synthetic token only.", flush=True)
    server.serve_forever()
