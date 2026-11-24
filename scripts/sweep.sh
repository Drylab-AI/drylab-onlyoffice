#!/usr/bin/env bash
# sweep.sh <out-dir> <label-prefix> [extra query]
# Responsive sweep (test only): for each fixture and width, open the editor
# in the harness, click every visible toolbar tab, screenshot it and run
# audit.js. Writes <out>/<prefix>-<ext>-<tab>-<w>.png and one
# <out>/<prefix>-results.jsonl line per (file, width, tab).
set -euo pipefail
OUT="${1:?out dir}"; PREFIX="${2:?prefix}"; EXTRA="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$(ls -d ~/.nvm/versions/node/*/bin | tail -1):$PATH"
export AGENT_BROWSER_SESSION="${AGENT_BROWSER_SESSION:-office-editor-p15}"
WIDTHS="${WIDTHS:-1024 1280 1366 1440 1704 1920 390}"
FILES="${FILES:-report.docx sales.xlsx deck.pptx}"
mkdir -p "$OUT"; RES="$OUT/$PREFIX-results.jsonl"
LOOK="$OUT/$PREFIX-look.jsonl"; [ "${RESUME:-0}" = 1 ] || : > "$LOOK"; touch "$LOOK"
ABOUT="$OUT/$PREFIX-about.jsonl"; [ "${RESUME:-0}" = 1 ] || : > "$ABOUT"; touch "$ABOUT"
# RESUME=1 keeps earlier rows and skips (file, width) pairs already done.
[ "${RESUME:-0}" = 1 ] || : > "$RES"; touch "$RES"
iframe_js() { echo "(() => { const d=document.querySelector('iframe').contentDocument; $1 })()"; }
for f in $FILES; do
  ext="${f##*.}"
  for w in $WIDTHS; do
    h=900; [ "$w" = 390 ] && h=844; [ "$w" = 1024 ] && h=768
    if grep -q "\"file\": \"$ext\", \"width\": $w," "$RES"; then echo "$ext $w: done earlier"; continue; fi
    tabs=""
    # A first open now and then misses docReady in time: retry twice.
    for attempt in 1 2 3; do
      VW=$w VH=$h SETTLE=3 HARNESS_PORT="${HARNESS_PORT:-8786}" "$HERE/shoot.sh" "$OUT" "$PREFIX-$ext-load-$w" "$f" "$EXTRA&s=sw$w$attempt" >/dev/null 2>&1 || true
      tabs=$(agent-browser eval "$(iframe_js "return JSON.stringify([...d.querySelectorAll('#toolbar .tabs li.ribtab:not(.x-lone) a[data-tab]')].filter(a=>a.offsetParent).map(a=>a.dataset.tab))")" 2>/dev/null | python3 -c 'import sys,json
try: print(" ".join(json.loads(json.loads(sys.stdin.read()))))
except Exception: print("")')
      [ -n "$tabs" ] && break
    done
    [ -n "$tabs" ] || { echo "$ext $w: FAILED to load" ; echo "{\"file\": \"$ext\", \"width\": $w, \"tabId\": \"load\", \"issues\": [\"editor did not load\"]}" >> "$RES"; continue; }
    # About button: one check per (file, width) on load.
    agent-browser eval "$(cat "$HERE/about-check.js")" | python3 -c "
import sys,json
v=json.loads(json.loads(sys.stdin.read())); v.update(file='$ext', width=$w)
print(json.dumps(v))" >> "$ABOUT"
    # Sheets / Slides look: one audit per (file, width) on load.
    [ "$ext" != docx ] && agent-browser eval "$(cat "$HERE/audit-sheets.js")" | python3 -c "
import sys,json
v=json.loads(json.loads(sys.stdin.read())); v.update(file='$ext', width=$w)
print(json.dumps(v))" >> "$LOOK"
    for t in $tabs; do
      agent-browser eval "$(iframe_js "const a=d.querySelector('#toolbar .tabs a[data-tab=\"$t\"]'); a.scrollIntoView({inline:'nearest'}); a.click(); return 1")" >/dev/null
      sleep 1.2
      agent-browser screenshot "$OUT/$PREFIX-$ext-$t-$w.png" >/dev/null
      agent-browser eval "$(cat "$HERE/audit.js")" | python3 -c "
import sys,json
v=json.loads(json.loads(sys.stdin.read())); v.update(file='$ext', width=$w, tabId='$t', png='$PREFIX-$ext-$t-$w.png')
print(json.dumps(v))" >> "$RES"
    done
    echo "$ext $w: $(echo $tabs | wc -w) tabs"
  done
done
python3 - "$RES" <<'PY'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1])]
bad=[r for r in rows if r['issues']]
print(f"{len(rows)} tab x width checks, {len(bad)} with issues")
for r in bad: print(r['file'], r['width'], r['tabId'], '|', '; '.join(r['issues'][:4]))
PY
python3 - "$LOOK" <<'PY'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad=[r for r in rows if r.get('issues')]
print(f"look: {len(rows)} file x width checks, {len(bad)} with issues")
for r in bad: print(' ', r['file'], r['width'], '|', '; '.join(r['issues'][:6]))
PY
python3 - "$ABOUT" <<'PY'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad=[r for r in rows if r.get('issues')]
print(f"about: {len(rows)} file x width checks, {len(bad)} with issues")
for r in bad: print(' ', r['file'], r['width'], '|', '; '.join(r['issues'][:6]))
PY
