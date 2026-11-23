"""Local test harness for the Drylab ONLYOFFICE build (stdlib only).

Not part of the image. It stands in for the Drylab backend + frontend so the
modified DocServer can be checked on one machine:

- serves the fixture files and an editor page that loads DocsAPI from the
  DocServer, with the same ``editorConfig.customization`` the Drylab backend
  sends (keep CUSTOMIZATION in sync with the integrator's config);
- signs the config, ``insertImage`` and ``setHistoryData`` payloads (HS256);
- receives the save callback and keeps every saved file under ``out/``;
- wires the Community events Drylab uses (rename, sharing, insert image,
  close; history only with ``cfg=v1``) and records each one in
  ``window.__events``;
- draws a mock of the Drylab editor bar above the iframe (``bar=v1|v2|none``)
  so screenshots show the whole header block.

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
# Layout v2: rulers on for Word, comments and chat off.
CUSTOMIZATION = {
    "forcesave": True,
    "autosave": True,
    "compactHeader": True,
    "toolbarHideFileName": True,
    "help": False,
    "feedback": False,
    # : no File > "Suggest a Feature".
    "suggestFeature": False,
    "uiTheme": "theme-white",
    "features": {"tabStyle": "line", "tabBackground": "toolbar", "featuresTips": False},
    "hideRightMenu": True,
    "hideRulers": False,
    "plugins": False,
    "comments": False,
    "chat": False,
    "close": {"visible": True},
}
# Same as the backend's document.permissions for an editor. :
# ``protect: False`` drops the Protection tab (``cfg=v2`` = without
# it, for before shots against drylab.2).
PERMISSIONS = {"edit": True, "comment": False, "chat": False, "download": True, "print": True, "review": False, "protect": False}
PERMISSIONS_V2 = {k: v for k, v in PERMISSIONS.items() if k != "protect"}
# ``cfg=v1``: the config (rulers hidden, comments + chat on), for
# before shots against the drylab.1 image.
CUSTOMIZATION_V1 = {k: v for k, v in CUSTOMIZATION.items() if k not in ("comments", "chat")}
CUSTOMIZATION_V1["hideRulers"] = True
PERMISSIONS_V1 = {"edit": True, "comment": True, "download": True, "print": True, "review": False}


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


def editor_config(name: str, suffix: str, lang: str, extra: dict | None = None, version: str = "v3") -> dict:
    ext = name.rsplit(".", 1)[-1]
    v1 = version == "v1"
    cust = json.loads(json.dumps(CUSTOMIZATION_V1 if v1 else CUSTOMIZATION))
    cust.update(extra or {})
    if DOC_TYPES[ext] == "word":
        cust["zoom"] = -2
    cfg = {
        "documentType": DOC_TYPES[ext],
        "document": {
            "fileType": ext,
            "key": doc_key(name, suffix),
            "title": name,
            "url": file_url(name),
            "permissions": dict(PERMISSIONS_V1 if v1 else PERMISSIONS_V2 if version == "v2" else PERMISSIONS),
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
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body{{margin:0;height:100%}}body{{display:flex;flex-direction:column}}#ed-wrap{{flex:1;min-height:0}}#ed{{height:100%}}{barcss}</style>
<script>window.__t0 = performance.now(); window.__events = [];</script>
<script src="{ds}/web-apps/apps/api/documents/api.js"></script></head>
<body>{bar}<div id="ed-wrap"><div id="ed"></div></div>{foot}<script>
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

# Mock of the Drylab editor bar above the iframe (the integrator's header), so
# shots show the whole header block. ``bar=v1``: the bar (48 px,
# bottom border, save state in words). ``bar=v2`` (default): layout v2, no
# border, save state as a cloud icon, the same title x the theme's
# --drylab-menu-indent assumes (93 px from 640 px up, 57 px below).
# ``bar=v3``: 15 px title and Save instead of Done, same title x.
# ``bar=v4`` (default ): no save cloud, no (i), a 16 px file icon in
# the 24 px slot, the muted notice line at the right (a thin line under the
# editor below 1024 px). ``bar=none`` drops it. Static HTML: it only has to
# look like the real bar.
ICONS = {
    "back": '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    "download": '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    "users": '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    "info": '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    "cloud": '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/><path d="m9.5 14 2 2 3.5-3.5"/>',
}
FILE_COLORS = {"docx": "#2B6CE6", "xlsx": "#1E8E3E", "pptx": "#E8710A"}


def svg(name: str, size: int = 20) -> str:
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>')


BAR_CSS = """
#bar{display:flex;align-items:center;gap:8px;padding:0 12px;height:48px;background:#fff;font-family:Inter,'Segoe UI',Arial,sans-serif;color:#28282A;flex-shrink:0}
#bar.v1{border-bottom:1px solid #E0E0E0}
#bar .ib{display:inline-flex;align-items:center;justify-content:center;width:36px;height:36px;border-radius:50%;color:#434348;flex-shrink:0}
#bar .ib.sm{width:32px;height:32px}
#bar .fi{width:24px;height:24px;border-radius:4px;flex-shrink:0}
#bar .title{font-size:18px;line-height:28px;padding:0 4px;border:1px solid transparent;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#bar .st{display:inline-flex;align-items:center;gap:6px;font-size:12px;color:#717176;white-space:nowrap}
#bar .sp{flex:1}
#bar .share{display:inline-flex;align-items:center;gap:6px;height:36px;padding:0 16px;border-radius:999px;background:#009D51;color:#fff;font-size:14px;font-weight:500}
#bar .done{display:inline-flex;align-items:center;height:36px;padding:0 16px;border-radius:999px;border:1px solid #DEDEDE;font-size:14px;font-weight:500;min-width:40px;justify-content:center}
#bar.v3 .title{font-size:15px;line-height:24px}
#bar.v3 .done{height:32px;font-size:13px;padding:0 14px}
#bar.v3 .share{height:32px;font-size:13px;padding:0 14px}
#bar.v4 .title{font-size:15px;line-height:24px}
#bar.v4 .done{height:32px;font-size:13px;padding:0 14px}
#bar.v4 .share{height:32px;font-size:13px;padding:0 14px}
#bar.v4 .fi{display:inline-flex;align-items:center;justify-content:center;background:none!important}
#bar .note{font-size:11px;line-height:16px;color:#8A8A8F;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
#foot-note{font-size:11px;line-height:16px;color:#8A8A8F;text-align:center;padding:3px 12px;border-top:1px solid #F2F2F2;background:#fff;flex-shrink:0}
@media (min-width:1024px){#foot-note{display:none}}
@media (max-width:1023px){#bar .note{display:none}}
@media (max-width:639px){#bar.v4 .fi{display:none}}
@media (max-width:639px){#bar{gap:4px;padding:0 4px;height:56px}#bar .ib{width:44px;height:44px}#bar .fi,#bar .lbl,#bar .dl,#bar .st .lbl{display:none}#bar .share{height:44px;padding:0 12px}#bar .done{height:44px;padding:0 12px}}
"""


NOTE = "Based on the open-source ONLYOFFICE Docs (AGPL v3)"
FILE_ICON_V4 = '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>'


def bar_html(name: str, version: str) -> str:
    color = FILE_COLORS.get(name.rsplit(".", 1)[-1], "#717176")
    if version == "v4":
        icon = (f'<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="2" '
                f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{FILE_ICON_V4}</svg>')
        return (f'<header id="bar" class="v4" data-drylab-bar="v4"><span class="ib">{svg("back")}</span>'
                f'<span class="fi">{icon}</span><span class="title" id="bar-title">{name}</span>'
                f'<span class="sp"></span><span class="note" title="ONLYOFFICE is a trademark of Ascensio System SIA.">{NOTE}</span>'
                f'<span class="ib dl" title="Download">{svg("download")}</span>'
                f'<span class="share">{svg("users", 16)}<span class="lbl">Share</span></span><span class="done">Save</span></header>')
    status = (f'<span class="st">{svg("cloud", 16)}<span class="lbl">All changes saved</span></span>' if version == "v1"
              else f'<span class="st" title="All changes saved">{svg("cloud", 18)}</span>')
    about = f'<span class="ib{" sm" if version != "v1" else ""}" title="About this editor">{svg("info", 18 if version != "v1" else 20)}</span>'
    # v3: 15 px title, Save instead of Done.
    done = "Save" if version == "v3" else "Done"
    right = (f'<span class="ib dl">{svg("download")}</span><span class="share">{svg("users", 16)}<span class="lbl">Share</span></span>{about}<span class="done">Done</span>'
             if version == "v1" else
             f'<span class="ib dl" title="Download">{svg("download")}</span>{about}<span class="share">{svg("users", 16)}<span class="lbl">Share</span></span><span class="done">{done}</span>')
    return (f'<header id="bar" class="{version}" data-drylab-bar="{version}"><span class="ib">{svg("back")}</span>'
            f'<span class="fi" style="background:{color}"></span><span class="title" id="bar-title">{name}</span>{status}'
            f'<span class="sp"></span>{right}</header>')


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
# Layout v2: version history removed from the editor, so no
# history events (ONLYOFFICE then drops File > Version History).
DRYLAB_EVENTS_V2 = "\n".join(l for l in DRYLAB_EVENTS.splitlines() if "History" not in l)


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
            cfg = editor_config(name, s, q.get("lang", "en"), json.loads(q.get("cust", "{}")), q.get("cfg", "v3"))
            events = "" if q.get("events") == "none" else (DRYLAB_EVENTS if q.get("cfg") == "v1" else DRYLAB_EVENTS_V2).format(
                qname=urllib.parse.quote(name), qs=urllib.parse.quote(s)
            )
            bar_v = q.get("bar", "v4")
            bar = "" if bar_v == "none" else bar_html(name, bar_v)
            foot = f'<div id="foot-note" title="ONLYOFFICE is a trademark of Ascensio System SIA.">{NOTE}</div>' if bar_v == "v4" else ""
            page = PAGE.format(name=name, ds=DS_BROWSER, cfg=json.dumps(cfg), events=events, bar=bar, foot=foot, barcss=BAR_CSS if bar else "")
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
        if u.path == "/meta":
            # Rename refresh: CommandService {c: meta} sets the open editor's title.
            cmd = {"c": "meta", "key": doc_key(q["name"], q.get("s", "")), "meta": {"title": q["title"]}}
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
            url = data["url"].replace(os.environ.get("DS_CB_HOST", "http://host.docker.internal:8085"), DS_INTERNAL)
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
