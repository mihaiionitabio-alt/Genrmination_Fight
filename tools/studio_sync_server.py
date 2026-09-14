"""Receives script sources posted by Roblox Studio and writes them into src/.

Studio has no file API: a script cannot write to disk. It can, however, make
HTTP requests, so the sync runs in that direction — Studio pushes, this listens.
Bind to loopback only; nothing leaves the machine.

    python tools/studio_sync_server.py        # then run tools/capture.lua in Studio
"""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import json, re, sys

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
PORT = 8770
MAX_BYTES = 8 * 1024 * 1024
SAFE = re.compile(r"^[A-Za-z0-9_.]+$")          # dotted DataModel path, nothing else
written, skipped = [], []


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/script":
            self.send_error(404); return
        n = int(self.headers.get("Content-Length", "0"))
        if n <= 0 or n > MAX_BYTES:
            self.send_error(413); return
        try:
            payload = json.loads(self.rfile.read(n))
            path, source = payload["path"], payload["source"]
        except Exception:
            self.send_error(400); return
        # A path segment must look like an instance name. This is the only thing
        # standing between a malformed capture and a write outside src/.
        if not SAFE.match(path) or ".." in path:
            skipped.append(path); self.send_error(400); return
        SRC.mkdir(exist_ok=True)
        target = (SRC / f"{path}.lua").resolve()
        if SRC.resolve() not in target.parents:
            skipped.append(path); self.send_error(400); return
        target.write_text(source, encoding="utf-8", newline="\n")
        written.append(path)
        print(f"  {path}  ({len(source):,} chars)")
        self.send_response(200); self.end_headers(); self.wfile.write(b"OK")

    def do_GET(self):
        if self.path == "/done":
            print(f"\n{len(written)} scripts written to src/"
                  + (f", {len(skipped)} rejected: {skipped}" if skipped else ""))
            self.send_response(200); self.end_headers(); self.wfile.write(b"OK")
            # flush before the server is torn down by Ctrl-C
            sys.stdout.flush()
        else:
            self.send_error(404)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"Listening on http://127.0.0.1:{PORT} — writing into {SRC}")
    print("Now run tools/capture.lua inside Studio (Edit mode). Ctrl-C when it finishes.\n")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
