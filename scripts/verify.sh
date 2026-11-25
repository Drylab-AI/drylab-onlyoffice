#!/usr/bin/env bash
# verify.sh: build the image, run it on 127.0.0.1 and check the modification.
#
# Static checks (curl, no browser): the server is healthy, each editor's
# index.html (plain and gzip) links drylab.css with the "Modified by Drylab"
# comment, drylab.css is served, ONLYOFFICE's LICENSE.txt is untouched, and
# the theme keeps the logo visible and carries the modified notice, and
# NOTICE says where the integrator's notice line is shown and carries the
# complete notices (ONLYOFFICE's own About entry is hidden), the
# spreadsheet patches are served, and each editor's left strip has the
# Drylab About button.
#
# With --browser it also runs the harness + headless agent-browser and
# saves before/after screenshots and DOM facts to $OUT (see README).
#
# Usage: JWT_SECRET=<secret> scripts/verify.sh [--browser] [--keep]
# Never binds 0.0.0.0, never pushes the image anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8085}"
NAME="${NAME:-drylab-onlyoffice-verify}"
IMAGE="${IMAGE:-drylab-onlyoffice:10.0.0.1-drylab.6}"
OUT="${OUT:-$PWD/scripts/out/evidence}"
BROWSER=0; KEEP=0
for a in "$@"; do case "$a" in --browser) BROWSER=1 ;; --keep) KEEP=1 ;; esac; done
: "${JWT_SECRET:?set JWT_SECRET (any 32+ char string for a local run)}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

docker build -q -t "$IMAGE" . >/dev/null && ok "built $IMAGE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "127.0.0.1:${PORT}:80" --add-host host.docker.internal:host-gateway \
  -e JWT_ENABLED=true -e JWT_SECRET="$JWT_SECRET" -e JWT_HEADER=AuthorizationJwt -e JWT_IN_BODY=true \
  -e ALLOW_PRIVATE_IP_ADDRESS=true -e WOPI_ENABLED=false "$IMAGE" >/dev/null
cleanup() { [ "$KEEP" = 1 ] || docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for _ in $(seq 60); do [ "$(curl -s "127.0.0.1:${PORT}/healthcheck")" = true ] && break; sleep 3; done
[ "$(curl -s "127.0.0.1:${PORT}/healthcheck")" = true ] || fail "healthcheck"
ok "healthcheck"
# The start-up script regenerates .gz copies and reloads nginx: let it finish.
sleep 30

base="http://127.0.0.1:${PORT}/web-apps/apps"
for e in documenteditor spreadsheeteditor presentationeditor; do
  plain=$(curl -sL "$base/$e/main/index.html")
  gz=$(curl -sL --compressed -H 'Accept-Encoding: gzip' "$base/$e/main/index.html")
  grep -q 'drylab/drylab.css' <<<"$plain" || fail "$e index.html has no drylab.css link"
  grep -q 'drylab/drylab.css' <<<"$gz" || fail "$e gzip index.html has no drylab.css link"
  grep -q 'Modified by Drylab on' <<<"$plain" || fail "$e index.html has no modified notice"
  ok "$e links the theme (plain + gzip) with the modified notice"
done
css=$(curl -sfL "$base/common/main/resources/drylab/drylab.css") || fail "drylab.css not served"
grep -q 'modified version of ONLYOFFICE Docs' <<<"$css" || fail "modified notice missing from drylab.css"
grep -q 'Ascensio System SIA' <<<"$css" || fail "attribution missing from drylab.css"
# Licence gate: no rule aimed at the logo may hide it (whole-file parse,
# rules span lines).
printf "%s" "$css" > /tmp/drylab-verify.css
python3 - /tmp/drylab-verify.css <<'PY' || fail "drylab.css hides the ONLYOFFICE logo"
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    if "header-logo" not in sel:
        continue
    b = re.sub(r"\s+", "", body)
    m = re.search(r"opacity:([0-9.]+)", b)
    if re.search(r"display:none|visibility:hidden|width:0[;p]|height:0[;p]", b) or (m and float(m.group(1)) < 0.4):
        sys.exit(f"hides logo: {sel.strip()}")
PY
# ONLYOFFICE's own left-strip About entry is hidden on purpose; the About
# button takes its place. NOTICE must say where the legal notices are, carry
# the complete notices itself, and name the exact upstream revisions.
for needle in "Where the legal notices are shown" "MODIFIED VERSION" "Ascensio System SIA" \
  "WITHOUT ANY WARRANTY" "(c) Ascensio System SIA" \
  "https://github.com/Drylab-AI/drylab-onlyoffice" "ONLYOFFICE/web-apps               v10.0.0.169" \
  "ONLYOFFICE/sdkjs                  v10.0.0.169" "ONLYOFFICE/server                 v10.0.0.169" \
  "ONLYOFFICE is a trademark of Ascensio System SIA"; do
  grep -qF "$needle" NOTICE || fail "NOTICE lacks: $needle"
done
ok "drylab.css served, modified notice present, logo not hidden; NOTICE says where the legal notices are"
# scripts/patch-js.sh: the served sdk-all.js carries the two
# new grid constants (not the stock ones) and the spreadsheet Main.js the
# blurfocus listener, plain and gzip, each with its modified-file line.
sdk="http://127.0.0.1:${PORT}/sdkjs/cell/sdk-all.js"
for enc in identity gzip; do
  body=$(curl -sL --compressed -H "Accept-Encoding: $enc" "$sdk")
  grep -qF 'this.TXa=new r(0,157,81);' <<<"$body" || fail "sdk-all.js ($enc) lacks the accent selection colour"
  grep -qF 'border:new r(226,227,227)},padding:-1}' <<<"$body" || fail "sdk-all.js ($enc) lacks the light grid colour"
  grep -qF 'this.TXa=new r(72,121,92);' <<<"$body" && fail "sdk-all.js ($enc) still has the stock selection colour"
  grep -qF 'Modified by Drylab on' <<<"$body" || fail "sdk-all.js ($enc) has no modified-file line"
done
main="http://127.0.0.1:${PORT}/web-apps/apps/spreadsheeteditor/main/app/controller/Main.js"
for enc in identity gzip; do
  body=$(curl -sL --compressed -H "Accept-Encoding: $enc" "$main")
  grep -qF "Common.Gateway.on('blurfocus'" <<<"$body" || fail "spreadsheet Main.js ($enc) lacks the blurfocus listener"
  grep -qF 'Modified by Drylab on' <<<"$body" || fail "spreadsheet Main.js ($enc) has no modified-file line"
done
ok "sdk-all.js has the Drylab grid colours, spreadsheet Main.js the blurfocus listener (plain + gzip, modified-file lines)"
# scripts/patch-about.sh: each editor's left menu template has
# the About button and its view the internalMessage click, plain and gzip,
# each with its modified-file line; NOTICE says where the notices now are.
for e in documenteditor spreadsheeteditor presentationeditor; do
  for enc in identity gzip; do
    tpl=$(curl -sL --compressed -H "Accept-Encoding: $enc" "$base/$e/main/app/template/LeftMenu.template")
    view=$(curl -sL --compressed -H "Accept-Encoding: $enc" "$base/$e/main/app/view/LeftMenu.js")
    grep -qF 'id="left-btn-drylab-about"' <<<"$tpl" || fail "$e LeftMenu.template ($enc) lacks the About button"
    grep -qF 'Modified by Drylab on' <<<"$tpl" || fail "$e LeftMenu.template ($enc) has no modified-file line"
    grep -qF "internalMessage('drylab:about'" <<<"$view" || fail "$e LeftMenu.js ($enc) lacks the About click"
    grep -qF 'Modified by Drylab on' <<<"$view" || fail "$e LeftMenu.js ($enc) has no modified-file line"
  done
done
grep -qF '"About" (i) button at the bottom of its left strip' NOTICE || fail "NOTICE does not say the notices are behind the About button"
ok "About button in each editor's left menu (template + view, plain + gzip, modified-file lines); NOTICE points at it"
docker exec -i "$NAME" cmp -s /var/www/onlyoffice/documentserver/LICENSE.txt /dev/stdin < LICENSE || fail "LICENSE differs from the image's LICENSE.txt"
ok "LICENSE matches the upstream LICENSE.txt"
docker exec "$NAME" test -f /var/www/onlyoffice/documentserver/DRYLAB-NOTICE.txt || fail "NOTICE not in the image"
ok "NOTICE shipped in the image"

if [ "$BROWSER" = 1 ]; then
  HPORT="${HARNESS_PORT:-8786}"
  # DS first: prefix assignments expand left to right, so PORT=... must not
  # come before a value that reads the DocServer's $PORT.
  DS="http://127.0.0.1:${PORT}"
  JWT_SECRET="$JWT_SECRET" DS_BROWSER="$DS" DS_INTERNAL="$DS" PORT="$HPORT" \
    setsid python3 -u scripts/harness.py > /tmp/drylab-oo-harness.log 2>&1 < /dev/null &
  HPID=$!
  trap 'kill $HPID 2>/dev/null; agent-browser close >/dev/null 2>&1; cleanup' EXIT
  sleep 1
  export AGENT_BROWSER_SESSION="${AGENT_BROWSER_SESSION:-drylab-oo-verify}"
  for f in report.docx sales.xlsx deck.pptx; do
    HARNESS_PORT="$HPORT" scripts/shoot.sh "$OUT" "after-${f%%.*}-${f##*.}" "$f"
    python3 - "$OUT/after-${f%%.*}-${f##*.}.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
assert j["drylabCss"], "theme not linked in the editor"
assert j["drylabVar"] == "#009D51", "theme variables not applied"
assert isinstance(j["logo"], dict) and float(j["logo"]["opacity"]) > 0.3, "logo hidden"
assert j["logoCovered"] == "visible", "logo covered: " + j["logoCovered"]
print("ok:", sys.argv[1].rsplit("/", 1)[-1], "theme applied, logo visible")
PY
    # File > Info still opens (ONLYOFFICE's document info panel), and the
    # items this build hides stay hidden.
    agent-browser eval "(() => { const d = document.querySelector('iframe').contentDocument; d.querySelector('#toolbar .tabs a[data-tab=file]').click(); return 1 })()" >/dev/null
    sleep 1.5
    agent-browser eval "(() => { const d = document.querySelector('iframe').contentDocument; const b = d.querySelector('#fm-btn-info'); b && b.click(); return 1 })()" >/dev/null
    sleep 1.5
    agent-browser eval "(() => {
      const d = document.querySelector('iframe').contentDocument;
      const shown = (s) => { const e = d.querySelector(s); if (!e) return false; const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== 'hidden'; };
      const tabs = [...d.querySelectorAll('#toolbar .tabs li.ribtab a')].filter((a) => a.offsetParent).map((a) => a.dataset.tab);
      return JSON.stringify({ info: shown('#panel-info') && d.querySelector('#panel-info').innerText.trim().length > 0,
        about: shown('#left-btn-about'), users: shown('#tlb-box-users'), mode: shown('#slot-btn-edit-mode'), close: shown('#slot-btn-close'),
        review: tabs.includes('review'), protect: tabs.includes('protect'),
        support: shown('#left-btn-support'), help: shown('#fm-btn-help'), suggest: shown('#fm-btn-suggest') });
    })()" | python3 -c '
import json, sys
j = json.loads(json.loads(sys.stdin.read()))
assert j["info"], "File > Info did not open"
for k in ("about", "users", "mode", "close", "review", "protect", "support", "help", "suggest"):
    assert not j[k], k + " is shown"
print("ok: File > Info opens; About, Feedback & Support, Help, Suggest a Feature, users, mode switch, close, Collaboration and Protection hidden")'
  done
  # The About button sits at the bottom of the strip, overlaps
  # nothing, and its click reaches the integrator (harness About dialog).
  for f in report.docx sales.xlsx deck.pptx; do
    HARNESS_PORT="$HPORT" scripts/shoot.sh "$OUT" "about-${f##*.}" "$f" >/dev/null
    agent-browser eval "$(cat scripts/about-check.js)" | python3 -c '
import json, sys
j = json.loads(json.loads(sys.stdin.read()))
assert not j["issues"], j
print("ok: About button at the bottom of the strip", j["btn"])'
    agent-browser eval "(() => { document.querySelector('iframe').contentDocument.querySelector('#left-btn-drylab-about').click(); return 1 })()" >/dev/null
    sleep 1
    agent-browser eval "JSON.stringify({open: !document.getElementById('about-dlg').hidden, ev: window.__events.includes('about')})" | python3 -c '
import json, sys
j = json.loads(json.loads(sys.stdin.read()))
assert j["open"] and j["ev"], j
print("ok: About click opens the integrator dialog")'
    agent-browser screenshot "$OUT/about-${f##*.}-open.png" >/dev/null
  done
  # Spreadsheet / presentation look (formula bar, headers, sheet
  # tabs, thumbnails, notes) on a fresh open of each file.
  for f in sales.xlsx deck.pptx; do
    HARNESS_PORT="$HPORT" scripts/shoot.sh "$OUT" "look-${f%%.*}" "$f" >/dev/null
    agent-browser eval "$(cat scripts/audit-sheets.js)" | python3 -c '
import json, sys
j = json.loads(json.loads(sys.stdin.read()))
assert not j["issues"], j
print("ok:", j["kind"], "look audit clean")'
  done
fi
echo "all checks passed"
