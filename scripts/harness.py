"""Local test harness for the Drylab ONLYOFFICE build (stdlib only).

Not part of the image. It stands in for the Drylab backend + frontend so the
modified DocServer can be checked on one machine:

- serves the fixture files and an editor page that loads DocsAPI from the
  DocServer, with the same ``editorConfig.customization`` the Drylab backend
  sends (keep CUSTOMIZATION in sync with the integrator's config);
- signs the config, ``insertImage`` and ``setHistoryData`` payloads (HS256);
- receives the save callback and keeps every saved file under ``out/``;
- wires the Community events Drylab uses (rename, history, sharing, insert
  image, close) and records each one in ``window.__events``.

Binds 127.0.0.1 (browser) and the docker0 bridge IP (DocServer callbacks)
only, never 0.0.0.0.
"""

import base64
import hashlib
import hmac
import json
import os
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
FILES = ROOT / "fixtures"
OUT = ROOT / "out"
SECRET = os.environ["JWT_SECRET"]
PORT = int(os.environ.get("PORT", "8786"))
BRIDGE_IP = os.environ.get("BRIDGE_IP", "172.17.0.1")
DS_BROWSER = os.environ.get("DS_BROWSER", "http://127.0.0.1:8085")
DS_INTERNAL = os.environ.get("DS_INTERNAL", "http://127.0.0.1:8085")
HOST_FOR_DS = os.environ.get("HOST_FOR_DS", f"http://host.docker.internal:{PORT}")
LOG = OUT / "callbacks.jsonl"

DOC_TYPES = {"docx": "word", "xlsx": "cell", "pptx": "slide"}
# Same as the integrator's editor customization (+ zoom for word).
CUSTOMIZATION = {
    "forcesave": True,
    "autosave": True,
    "compactHeader": True,
    "toolbarHideFileName": True,
    "help": False,
    "feedback": False,
    "uiTheme": "theme-white",
    "features": {"tabStyle": "line", "tabBackground": "toolbar", "featuresTips": False},
    "hideRightMenu": True,
    "hideRulers": True,
    "plugins": False,
}


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt_encode(payload: dict) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64url(json.dumps(payload, separators=(",", ":")).encode())
    sig = hmac.new(SECRET.encode(), f"{header}.{body}".encode(), hashlib.sha256).digest()
    return f"{header}.{body}.{b64url(sig)}"


def jwt_decode(token: str) -> dict:
    header, body, sig = token.split(".")
    want = b64url(hmac.new(SECRET.encode(), f"{header}.{body}".encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(want, sig):
        raise ValueError("bad signature")
    return json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))


def doc_key(name: str, suffix: str = "") -> str:
    st = (FILES / name).stat()
    return hashlib.sha256(f"{name}-{st.st_mtime_ns}-{st.st_size}{suffix}".encode()).hexdigest()[:40]


def file_url(name: str) -> str:
    return f"{HOST_FOR_DS}/files/{urllib.parse.quote(name)}"


def editor_config(name: str, suffix: str, lang: str) -> dict:
    ext = name.rsplit(".", 1)[-1]
    cust = json.loads(json.dumps(CUSTOMIZATION))
    if DOC_TYPES[ext] == "word":
        cust["zoom"] = -2
    cfg = {
        "documentType": DOC_TYPES[ext],
        "document": {
            "fileType": ext,
            "key": doc_key(name, suffix),
            "title": name,
            "url": file_url(name),
            "permissions": {"edit": True, "comment": True, "download": True, "print": True, "review": False},
        },
        "editorConfig": {
            "mode": "edit",
            "lang": lang,
            "callbackUrl": f"{HOST_FOR_DS}/callback?name={urllib.parse.quote(name)}",
            "user": {"id": "harness-user", "name": "Harness User"},
            "customization": cust,
        },
    }
    cfg["token"] = jwt_encode(cfg)
    return cfg


def history(name: str, suffix: str) -> dict:
    """Two fake versions: the original file (v1) and the current one (v2)."""
    key = doc_key(name, suffix)
    return {
        "currentVersion": 2,
        "history": [
            {"version": 1, "key": key + "v1", "created": "2026-11-20 10:00:00", "user": {"id": "harness-user", "name": "Harness User"}},
            {"version": 2, "key": key, "created": "2026-11-23 10:00:00", "user": {"id": "harness-user", "name": "Harness User"}},
        ],
    }


def history_data(name: str, suffix: str, version: int) -> dict:
    key = doc_key(name, suffix) + ("v1" if version == 1 else "")
    data = {"version": version, "key": key, "url": file_url(name), "fileType": name.rsplit(".", 1)[-1]}
    data["token"] = jwt_encode(dict(data))
    return data


def insert_image_payload() -> dict:
    payload = {"c": "add", "images": [{"fileType": "png", "url": file_url("green.png")}]}
    payload["token"] = jwt_encode(dict(payload))
    return payload


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>harness {name}</title>
<style>html,body{{margin:0;height:100%}}#ed{{height:100vh}}</style>
<script>window.__t0 = performance.now(); window.__events = [];</script>
<script src="{ds}/web-apps/apps/api/documents/api.js"></script></head>
<body><div id="ed"></div><script>
const cfg = {cfg};
const q = (p) => fetch(p).then(r => r.json());
const ev = (s) => window.__events.push(s);
cfg.events = {{
  onAppReady: () => {{ window.__appReady = performance.now() - window.__t0; ev('appReady'); }},
  onDocumentReady: () => {{ window.__docReady = performance.now() - window.__t0; ev('documentReady'); }},
  onError: (e) => ev('error:' + JSON.stringify(e.data)),
  onWarning: (e) => ev('warning:' + JSON.stringify(e.data)),
  onDocumentStateChange: (e) => ev('state:' + e.data),
  onDownloadAs: (e) => {{ ev('downloadAs:' + (e.data && e.data.fileType)); window.__downloadUrl = e.data && e.data.url; }},
  onMetaChange: (e) => ev('meta:' + JSON.stringify(e.data)),
  {events}
}};
window.docEditor = new DocsAPI.DocEditor('ed', cfg);
</script></body></html>"""

# The Community events Drylab wires. ``events=none`` drops them.
DRYLAB_EVENTS = """
  onRequestRename: (e) => ev('rename:' + e.data),
  onRequestSharingSettings: () => ev('share'),
  onRequestClose: () => ev('close'),
  onRequestInsertImage: (e) => {{ ev('insertImage:' + JSON.stringify(e.data)); q('/insert-image').then(p => window.docEditor.insertImage(p)); }},
  onRequestHistory: () => {{ ev('history'); q('/history?name={qname}&s={qs}').then(h => window.docEditor.refreshHistory(h)); }},
  onRequestHistoryData: (e) => {{ ev('historyData:' + e.data); q('/history-data?name={qname}&s={qs}&v=' + e.data).then(d => window.docEditor.setHistoryData(d)); }},
  onRequestHistoryClose: () => ev('historyClose'),
"""


class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("[harness] " + fmt % a + "\n")

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        if u.path.startswith("/files/"):
            p = FILES / urllib.parse.unquote(u.path[len("/files/"):])
            if not p.is_file():
                return self._send(404, {"error": "nf"})
            return self._send(200, p.read_bytes(), "application/octet-stream")
        if u.path == "/editor":
            name, s = q["name"], q.get("s", "")
            cfg = editor_config(name, s, q.get("lang", "en"))
            events = "" if q.get("events") == "none" else DRYLAB_EVENTS.format(
                qname=urllib.parse.quote(name), qs=urllib.parse.quote(s)
            )
            page = PAGE.format(name=name, ds=DS_BROWSER, cfg=json.dumps(cfg), events=events)
            return self._send(200, page, "text/html; charset=utf-8")
        if u.path == "/insert-image":
            return self._send(200, insert_image_payload())
        if u.path == "/history":
            return self._send(200, history(q["name"], q.get("s", "")))
        if u.path == "/history-data":
            return self._send(200, history_data(q["name"], q.get("s", ""), int(q.get("v", "2"))))
        if u.path == "/forcesave":
            cmd = {"c": "forcesave", "key": doc_key(q["name"], q.get("s", ""))}
            body = dict(cmd, token=jwt_encode(cmd))
            req = urllib.request.Request(
                f"{DS_INTERNAL}/command", data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json", "AuthorizationJwt": "Bearer " + jwt_encode(cmd)},
            )
            with urllib.request.urlopen(req, timeout=30) as r:
                return self._send(200, json.loads(r.read()))
        if u.path == "/saves":
            rows = [json.loads(x) for x in LOG.read_text().splitlines()] if LOG.exists() else []
            return self._send(200, rows)
        return self._send(404, {"error": "nf"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        if u.path != "/callback":
            return self._send(404, {"error": 1})
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        try:
            if not data.get("token"):
                return self._send(403, {"error": 1})
            data = jwt_decode(data["token"])
        except ValueError:
            return self._send(403, {"error": 1})
        name = q.get("name", "unknown")
        entry = {"t": time.time(), "name": name, **{k: data.get(k) for k in ("status", "forcesavetype", "filetype")}}
        if data.get("status") in (2, 6) and data.get("url"):
            stem, ext = name.rsplit(".", 1)
            out = OUT / f"{stem}.saved.{data['status']}.{int(time.time() * 1000)}.{ext}"
            url = data["url"].replace("http://host.docker.internal:8085", DS_INTERNAL)
            with urllib.request.urlopen(url, timeout=60) as r:
                out.write_bytes(r.read())
            entry.update(saved_to=out.name, bytes=out.stat().st_size)
        with LOG.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        return self._send(200, {"error": 0})


def serve(host):
    ThreadingHTTPServer((host, PORT), H).serve_forever()


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for h in ("127.0.0.1", BRIDGE_IP):
        threading.Thread(target=serve, args=(h,), daemon=True).start()
    print(f"harness on 127.0.0.1:{PORT} and {BRIDGE_IP}:{PORT}", flush=True)
    while True:
        time.sleep(3600)
