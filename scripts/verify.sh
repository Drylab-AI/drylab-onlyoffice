#!/usr/bin/env bash
# verify.sh: build the image, run it on 127.0.0.1 and check the modification.
#
# Static checks (curl, no browser): the server is healthy, each editor's
# index.html (plain and gzip) links drylab.css with the "Modified by Drylab"
# comment, drylab.css is served, ONLYOFFICE's LICENSE.txt is untouched, and
# the theme keeps the logo visible and carries the modified notice, and
# NOTICE says where the legal notices are shown (the in-editor About entry
# is hidden since drylab.3).
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
IMAGE="${IMAGE:-drylab-onlyoffice:10.0.0.1-drylab.3}"
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
# drylab.3: the left-strip About entry is hidden on purpose; the legal
# notices move to the integrator's (i) dialog. NOTICE must say so, and must
# carry the full notice text that dialog shows.
for needle in "Where the legal notices are shown" "WITHOUT ANY WARRANTY" "(c) Ascensio System SIA" \
  "https://github.com/Drylab-AI/drylab-onlyoffice" "https://github.com/ONLYOFFICE/DocumentServer" \
  "ONLYOFFICE is a trademark of Ascensio System SIA"; do
  grep -qF "$needle" NOTICE || fail "NOTICE lacks: $needle"
done
ok "drylab.css served, modified notice present, logo not hidden; NOTICE says where the legal notices are"
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
        review: tabs.includes('review'), protect: tabs.includes('protect') });
    })()" | python3 -c '
import json, sys
j = json.loads(json.loads(sys.stdin.read()))
assert j["info"], "File > Info did not open"
for k in ("about", "users", "mode", "close", "review", "protect"):
    assert not j[k], k + " is shown"
print("ok: File > Info opens; About entry, users, mode switch, close, Collaboration and Protection hidden")'
  done
fi
echo "all checks passed"
