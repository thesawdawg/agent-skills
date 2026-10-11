#!/usr/bin/env python3
"""Serve documents and data files as one themed, navigable page (stdlib only).

Loopback by default; --lan binds all interfaces. Every request needs a random
token. Only files registered at startup (never request paths) are readable.
"""
import argparse
import hashlib
import http.server
import json
import mimetypes
import os
import secrets
import socket
import sys
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ASSETS = Path(__file__).resolve().parent.parent / 'assets'
STATIC = {'/': 'index.html', '/app.js': 'app.js', '/style.css': 'style.css',
          '/vendor/marked.umd.js': 'vendor/marked.umd.js',
          '/vendor/highlight.min.js': 'vendor/highlight.min.js',
          '/vendor/mermaid.min.js': 'vendor/mermaid.min.js'}
TEXT_SUFFIXES = {'.md', '.markdown', '.txt', '.json', '.csv', '.tsv', '.diff',
                 '.patch', '.mmd', '.mermaid', '.yaml', '.yml', '.toml', '.ini',
                 '.log', '.py', '.js', '.mjs', '.ts', '.tsx', '.jsx', '.sh',
                 '.go', '.rs', '.java', '.c', '.h', '.cpp', '.rb', '.sql',
                 '.html', '.css', '.xml'}
SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', 'dist', 'build'}
SECRET_NAMES = {'.env', 'id_rsa', 'id_ed25519', 'credentials', '.netrc', '.npmrc'}
SECRET_SUFFIXES = {'.pem', '.key', '.p12', '.pfx', '.kdbx'}
MAX_BYTES = 5 * 1024 * 1024
MAX_FILES = 300
CSP = ("default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
       "img-src 'self' data:; font-src 'self' data:; connect-src 'self'; "
       "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")


def is_secret(path: Path) -> bool:
    """Return True for files that commonly hold credentials."""
    name = path.name.lower()
    return (name in SECRET_NAMES or name.startswith('.env.')
            or path.suffix.lower() in SECRET_SUFFIXES)


def collect(inputs: list[str]) -> tuple[list[Path], list[str]]:
    """Resolve input files/directories to a bounded, de-duplicated file list.

    Args:
        inputs: File or directory paths from the command line.
    Returns:
        (files, warnings) with symlinks resolved and secrets/oversize skipped.
    """
    files, warnings, seen = [], [], set()

    def add(path: Path, explicit: bool) -> None:
        real = path.resolve()
        if real in seen or not real.is_file():
            return
        if is_secret(real):
            warnings.append(f'skipped credential-like file: {real.name}')
        elif real.stat().st_size > MAX_BYTES:
            warnings.append(f'skipped >5MB file: {real.name}')
        elif explicit or real.suffix.lower() in TEXT_SUFFIXES:
            seen.add(real)
            files.append(real)

    for raw in inputs:
        path = Path(raw)
        if path.is_dir():
            for root, dirs, names in os.walk(path):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith('.'))
                for name in sorted(names):
                    if not name.startswith('.'):
                        add(Path(root) / name, False)
        elif path.exists():
            add(path, True)
        else:
            warnings.append(f'not found: {raw}')
    if len(files) > MAX_FILES:
        warnings.append(f'truncated to {MAX_FILES} files')
        files = files[:MAX_FILES]
    return files, warnings


def lan_address() -> str:
    """Best-effort primary LAN IPv4 address (no packets are sent)."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(('10.254.254.254', 1))
        return probe.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        probe.close()


class State:
    """Registered documents plus activity tracking for idle shutdown."""

    def __init__(self, files: list[Path], title: str, token: str):
        self.files, self.title, self.token = files, title, token
        self.last_request = time.monotonic()
        base = Path(os.path.commonpath([str(f.parent) for f in files])) if files else Path('.')
        self.names = [str(f.relative_to(base)) if f.is_relative_to(base) else f.name for f in files]

    def listing(self) -> list[dict]:
        """Metadata for each document, including a change fingerprint."""
        rows = []
        for index, path in enumerate(self.files):
            try:
                stat = path.stat()
                rows.append({'id': index, 'name': self.names[index], 'size': stat.st_size,
                             'mtime': stat.st_mtime_ns, 'ext': path.suffix.lower().lstrip('.')})
            except OSError:
                rows.append({'id': index, 'name': self.names[index], 'size': 0, 'mtime': 0,
                             'ext': path.suffix.lower().lstrip('.'), 'missing': True})
        return rows

    def version(self) -> str:
        """Short hash that changes whenever any served file changes."""
        digest = hashlib.sha1(json.dumps(self.listing()).encode()).hexdigest()
        return digest[:12]


def make_handler(state: State):
    """Build a request handler bound to one State."""

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = 'lan-viewer'

        def log_message(self, *_args):  # keep stdout reserved for the startup record
            pass

        def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('Content-Security-Policy', CSP)
            for key, value in (extra or {}).items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, payload) -> None:
            self._send(200, json.dumps(payload).encode(), 'application/json; charset=utf-8')

        def _authorized(self, query: dict) -> bool:
            cookie = self.headers.get('Cookie', '')
            presented = [query.get('t', [''])[0]]
            presented += [c.strip()[len('lv_token='):] for c in cookie.split(';')
                          if c.strip().startswith('lv_token=')]
            return any(secrets.compare_digest(p, state.token) for p in presented if p)

        def do_GET(self):  # noqa: N802 (http.server API)
            state.last_request = time.monotonic()
            parts = urlsplit(self.path)
            query = parse_qs(parts.query)
            if not self._authorized(query):
                self._send(403, b'Forbidden: open the full URL printed by viewer.py.\n',
                           'text/plain; charset=utf-8')
                return
            if query.get('t') and parts.path == '/':
                # Move the token into an HttpOnly cookie so it leaves history and referrers.
                cookie = f'lv_token={state.token}; Path=/; HttpOnly; SameSite=Strict'
                self.send_response(302)
                self.send_header('Location', '/')
                self.send_header('Set-Cookie', cookie)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if parts.path in STATIC:
                path = ASSETS / STATIC[parts.path]
                ctype = mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
                if ctype.startswith('text/') or ctype.endswith('javascript'):
                    ctype += '; charset=utf-8'
                self._send(200, path.read_bytes(), ctype)
            elif parts.path == '/api/docs':
                self._json({'title': state.title, 'version': state.version(), 'docs': state.listing()})
            elif parts.path == '/api/version':
                self._json({'version': state.version()})
            elif parts.path == '/api/doc':
                try:
                    path = state.files[int(query.get('id', [''])[0])]
                    text = path.read_text(encoding='utf-8', errors='replace')
                except (ValueError, IndexError, OSError):
                    self._send(404, b'Not found\n', 'text/plain; charset=utf-8')
                    return
                self._send(200, text.encode(), 'text/plain; charset=utf-8')
            else:
                self._send(404, b'Not found\n', 'text/plain; charset=utf-8')

    return Handler


def serve(args: argparse.Namespace) -> int:
    """Start the server, print one JSON startup record, and run until stopped."""
    files, warnings = collect(args.paths)
    if not files:
        print('No viewable files found.', *warnings, sep='\n', file=sys.stderr)
        return 2
    token = args.token or secrets.token_urlsafe(18)
    state = State(files, args.title, token)
    host = '0.0.0.0' if args.lan else '127.0.0.1'
    httpd = http.server.ThreadingHTTPServer((host, args.port), make_handler(state))
    port = httpd.server_address[1]
    address = lan_address() if args.lan else '127.0.0.1'
    record = {'url': f'http://{address}:{port}/?t={token}', 'bind': host, 'port': port,
              'pid': os.getpid(), 'files': len(files), 'lan': args.lan,
              'idle_timeout_min': args.idle_timeout, 'warnings': warnings}
    print(json.dumps(record), flush=True)

    def watchdog() -> None:
        while args.idle_timeout:
            time.sleep(5)
            if time.monotonic() - state.last_request > args.idle_timeout * 60:
                httpd.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


def selftest() -> int:
    """Exercise collection, secret filtering, and token enforcement on loopback."""
    import tempfile
    import urllib.error
    import urllib.request
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'a.md').write_text('# A\n')
        (root / '.env').write_text('SECRET=1\n')
        (root / 'node_modules').mkdir()
        (root / 'node_modules' / 'x.md').write_text('x')
        files, warnings = collect([tmp, str(root / '.env')])
        assert [f.name for f in files] == ['a.md'], files
        assert any('credential' in w for w in warnings), warnings
        state = State(files, 't', 'tok')
        httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), make_handler(state))
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = f'http://127.0.0.1:{httpd.server_address[1]}'
        try:
            urllib.request.urlopen(base + '/api/docs')
            raise AssertionError('unauthenticated request succeeded')
        except urllib.error.HTTPError as error:
            assert error.code == 403
        with urllib.request.urlopen(base + '/api/docs?t=tok') as reply:
            assert json.load(reply)['docs'][0]['name'] == 'a.md'
        httpd.shutdown()
        httpd.server_close()
    print('viewer selftest ok')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*', help='files or directories to serve')
    parser.add_argument('--lan', action='store_true', help='bind all interfaces (default: loopback only)')
    parser.add_argument('--port', type=int, default=0, help='port (default: random free port)')
    parser.add_argument('--title', default='Document viewer')
    parser.add_argument('--token', help='access token (default: random)')
    parser.add_argument('--idle-timeout', type=int, default=120, metavar='MIN',
                        help='stop after this many idle minutes; 0 disables (default 120)')
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if not args.paths:
        parser.error('give at least one file or directory')
    return serve(args)


if __name__ == '__main__':
    sys.exit(main())
