#!/usr/bin/env python3
"""Local web dashboard for the D.A.V.E. state tree.

Binds 127.0.0.1 only — the state tree is personal and never leaves the
machine. Prints one `READY http://127.0.0.1:<port>/` line once it is
serving so scripts can poll for it.

Usage: server.py --port N --dave-sh /path/to/dave.sh
DAVE_HOME selects the state tree (default ~/.dave).
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import secrets
import signal
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

from api import ApiError, DashboardApi  # noqa: E402
from dave_cli import DaveCli, DaveError  # noqa: E402

STATIC_DIR = Path(__file__).resolve().parent / "static"
SETUP_MESSAGES = {
    3: "D.A.V.E. is not set up here — run `dave.sh init` first.",
    4: "The state tree predates this version — run `dave.sh migrate`.",
}


class ChangeWatcher:
    """Tracks the newest mtime anywhere in the state tree.

    One thread polls every second; SSE subscribers read `generation`, which
    increments on each observed change. One level of subdirectories is
    scanned (log/, missions/, intake/, projects/<slug>/); .git is ignored.
    """

    def __init__(self, home: Path, interval: float = 1.0) -> None:
        """Bind the watcher to a directory.

        Args:
            home: The state directory to watch.
            interval: Poll interval in seconds.
        """
        self.home = home
        self.interval = interval
        self.generation = 0
        self.changed_at = datetime.now().astimezone().isoformat()
        self._latest = self._scan()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)

    def start(self) -> None:
        """Start the polling thread.

        Returns:
            None.
        """
        self._thread.start()

    def stop(self) -> None:
        """Signal the polling thread to exit.

        Returns:
            None.
        """
        self._stop.set()

    def _scan(self) -> float:
        """Newest mtime among top-level files and one level of subdirs.

        Returns:
            The maximum mtime seen, 0.0 for an empty/missing tree.
        """
        latest = 0.0
        try:
            entries = list(self.home.iterdir())
        except OSError:
            return latest
        for entry in entries:
            if entry.name == ".git":
                continue
            try:
                if entry.is_file():
                    latest = max(latest, entry.stat().st_mtime)
                elif entry.is_dir():
                    for child in entry.iterdir():
                        if child.is_file():
                            latest = max(latest, child.stat().st_mtime)
            except OSError:
                continue
        return latest

    def _loop(self) -> None:
        """Poll for mtime changes until stopped.

        Returns:
            None.
        """
        while not self._stop.wait(self.interval):
            newest = self._scan()
            if newest != self._latest:
                self._latest = newest
                self.generation += 1
                self.changed_at = datetime.now().astimezone().isoformat()


class DashboardServer(ThreadingHTTPServer):
    """HTTP server carrying the dashboard's shared objects."""

    def __init__(
        self,
        address: tuple[str, int],
        api: DashboardApi,
        token: str,
        watcher: ChangeWatcher,
    ) -> None:
        """Initialize the server with its handler dependencies.

        Args:
            address: (host, port) bind tuple.
            api: The route handlers.
            token: The CSRF token for this run.
            watcher: The state-tree change watcher.
        """
        super().__init__(address, DashboardHandler)
        self.api = api
        self.token = token
        self.watcher = watcher


class DashboardHandler(BaseHTTPRequestHandler):
    """Serves the SPA, the JSON API, and the SSE stream."""

    server_version = "DaveDashboard/1.0"
    protocol_version = "HTTP/1.1"

    @property
    def app(self) -> DashboardServer:
        """The server instance, typed for attribute access.

        Returns:
            The DashboardServer this handler runs under.
        """
        return self.server  # type: ignore[return-value]

    def log_message(self, fmt: str, *args: Any) -> None:
        """Quiet the default request log — stderr stays for real errors.

        Args:
            fmt: Log format string.
            *args: Format arguments.

        Returns:
            None.
        """

    # --------------------------------------------------------------- helpers

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        """Send a JSON response with the shared envelope already applied.

        Args:
            status: HTTP status code.
            payload: The full response body.

        Returns:
            None.
        """
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_data(self, status: int, data: Any) -> None:
        """Send a success-envelope JSON response.

        Args:
            status: HTTP status code.
            data: The data payload.

        Returns:
            None.
        """
        self._send_json(status, {"status": "success", "data": data})

    def _send_error(self, status: int, message: str) -> None:
        """Send an error-envelope JSON response.

        Args:
            status: HTTP status code.
            message: The error message.

        Returns:
            None.
        """
        self._send_json(status, {"status": "error",
                                 "errors": [{"message": message}]})

    def _map_error(self, exc: Exception) -> None:
        """Translate a raised exception into an error response.

        Args:
            exc: The exception raised by a handler.

        Returns:
            None.
        """
        if isinstance(exc, ApiError):
            self._send_error(exc.status, exc.message)
        elif isinstance(exc, DaveError):
            if exc.code in SETUP_MESSAGES:
                self._send_error(409, SETUP_MESSAGES[exc.code])
            else:
                detail = exc.stderr.strip() or str(exc)
                self._send_error(500, f"dave.sh failed (exit {exc.code}): {detail}")
        else:
            self._send_error(500, f"internal error: {exc}")

    def _check_post_security(self) -> bool:
        """Enforce the CSRF token and Origin rules on a POST.

        Returns:
            True when the request may proceed; the error is already sent
            when it returns False.
        """
        if self.headers.get("X-Dave-Token") != self.app.token:
            self._send_error(403, "missing or invalid X-Dave-Token")
            return False
        origin = self.headers.get("Origin")
        if origin is not None:
            host = self.headers.get("Host")
            if host:
                # The origin a browser just connected through is the origin we
                # served — this also covers a local proxy on another port.
                allowed = {f"http://{host}"}
            else:
                port = self.server.server_address[1]
                allowed = {f"http://127.0.0.1:{port}",
                           f"http://localhost:{port}"}
            if origin not in allowed:
                self._send_error(403, f"Origin not allowed: {origin}")
                return False
        return True

    # ------------------------------------------------------------------ GET

    def do_GET(self) -> None:
        """Route GET requests: SPA, static files, SSE, JSON API.

        Returns:
            None.
        """
        parsed = urlparse(self.path)
        path = parsed.path
        try:
            if path == "/":
                self._serve_index()
            elif path == "/api/events":
                self._serve_events()
            elif path.startswith("/static/"):
                self._serve_static(path)
            elif path.startswith("/api/"):
                data = self.app.api.dispatch_get(path, parse_qs(parsed.query))
                self._send_data(200, data)
            else:
                self._send_error(404, f"no such route: {path}")
        except (ApiError, DaveError) as exc:
            self._map_error(exc)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # noqa: BLE001 — last-resort envelope
            self._map_error(exc)

    def _serve_index(self) -> None:
        """index.html with the per-run CSRF token injected.

        Returns:
            None.
        """
        try:
            html = (STATIC_DIR / "index.html").read_text(encoding="utf-8")
        except OSError:
            self._send_error(500, "static assets missing")
            return
        token_meta = f'<meta name="dave-token" content="{self.app.token}">'
        html = html.replace("<meta name=\"dave-token\" content=\"\">", token_meta)
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_static(self, path: str) -> None:
        """A file under static/, traversal-safe by construction.

        Args:
            path: The URL path (/static/<name>).

        Returns:
            None.
        """
        name = Path(path).name
        target = STATIC_DIR / name
        if not target.is_file():
            self._send_error(404, f"no such asset: {name}")
            return
        body = target.read_bytes()
        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_events(self) -> None:
        """The SSE stream: `changed` events plus keepalive pings.

        Returns:
            None.
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        watcher = self.app.watcher
        seen = watcher.generation
        last_ping = time.monotonic()
        try:
            while True:
                if watcher.generation != seen:
                    seen = watcher.generation
                    payload = json.dumps({"at": watcher.changed_at})
                    self.wfile.write(f"event: changed\ndata: {payload}\n\n".encode())
                    self.wfile.flush()
                    last_ping = time.monotonic()
                elif time.monotonic() - last_ping >= 15:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    last_ping = time.monotonic()
                else:
                    time.sleep(1)
        except (BrokenPipeError, ConnectionResetError):
            return

    # ----------------------------------------------------------------- POST

    def do_POST(self) -> None:
        """Route POST requests through the CSRF checks into the API.

        Returns:
            None.
        """
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            self._send_error(404, f"no such route: {parsed.path}")
            return
        if not self._check_post_security():
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(min(length, 1024 * 1024)) if length > 0 else b""
        try:
            body = json.loads(raw) if raw else {}
            if not isinstance(body, dict):
                raise ValueError("body must be a JSON object")
        except (json.JSONDecodeError, ValueError) as exc:
            self._send_error(400, f"invalid JSON body: {exc}")
            return
        try:
            data = self.app.api.dispatch_post(parsed.path, body)
            self._send_data(200, data)
        except (ApiError, DaveError) as exc:
            self._map_error(exc)
        except Exception as exc:  # noqa: BLE001 — last-resort envelope
            self._map_error(exc)


def main() -> None:
    """Parse arguments, build the server, print READY, serve forever.

    Returns:
        None.
    """
    parser = argparse.ArgumentParser(description="D.A.V.E. local dashboard")
    parser.add_argument("--port", type=int, default=8766,
                        help="port to bind (0 = pick a free one)")
    parser.add_argument("--dave-sh", required=True, dest="dave_sh",
                        help="absolute path to dave.sh")
    args = parser.parse_args()

    dave_home = Path(os.environ.get("DAVE_HOME", str(Path.home() / ".dave")))
    cli = DaveCli(args.dave_sh, dave_home)
    api = DashboardApi(dave_home, cli)
    token = secrets.token_urlsafe(32)
    watcher = ChangeWatcher(dave_home)
    watcher.start()

    server = DashboardServer(("127.0.0.1", args.port), api, token, watcher)
    port = server.server_address[1]
    print(f"READY http://127.0.0.1:{port}/", flush=True)

    def _shutdown(signum: int, frame: Any) -> None:
        """Stop serving on SIGINT/SIGTERM without a deadlock.

        Args:
            signum: The received signal.
            frame: The current stack frame.

        Returns:
            None.
        """
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)
    try:
        server.serve_forever()
    finally:
        watcher.stop()
        server.server_close()


if __name__ == "__main__":
    main()
