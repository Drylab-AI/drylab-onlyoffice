#!/usr/bin/env bash
# shoot.sh <out-dir> <label> <file> [extra query]
# Open one fixture in the harness (headless agent-browser), wait for the
# document, save <label>.png and <label>.json (DOM facts from probe.js).
# The session runs with --disable-web-security so probe.js can read the
# DocServer iframe; this is a local test browser only.
set -euo pipefail
OUT="${1:?out dir}"; LABEL="${2:?label}"; FILE="${3:?fixture}"; EXTRA="${4:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$(ls -d ~/.nvm/versions/node/*/bin | tail -1):$PATH"
export AGENT_BROWSER_SESSION="${AGENT_BROWSER_SESSION:-office-editor-oo13}"
export AGENT_BROWSER_ARGS="--no-sandbox,--disable-web-security,--disable-site-isolation-trials"
mkdir -p "$OUT"
agent-browser set viewport "${VW:-1440}" "${VH:-900}" >/dev/null 2>&1 || true
agent-browser open "http://127.0.0.1:${HARNESS_PORT:-8786}/editor?name=${FILE}&s=${LABEL}${EXTRA}" >/dev/null
agent-browser wait --fn 'window.__docReady > 0' --timeout 120000 >/dev/null || echo "$LABEL: docReady timeout" >&2
sleep "${SETTLE:-4}"
agent-browser screenshot "$OUT/$LABEL.png" >/dev/null
agent-browser eval "$(cat "$HERE/probe.js")" | python3 -c 'import sys,json; v=json.loads(sys.stdin.read()); print(json.dumps(json.loads(v), indent=1))' > "$OUT/$LABEL.json"
echo "saved $OUT/$LABEL.png"
