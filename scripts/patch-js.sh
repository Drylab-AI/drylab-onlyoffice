#!/usr/bin/env bash
# Spreadsheet editor JS changes (build step drylab.5).
# Usage: patch-js.sh <documentserver dir> <modified date>
#
# Two small, separate changes; each must find its pattern exactly once or
# the build fails, so an ONLYOFFICE update that moves the code can't ship a
# half-patched image. Both files get a "Modified by Drylab" header line.
#
# 1. sdkjs/cell/sdk-all.js, grid colours. The grid is drawn on a canvas and
#    two of its colours are constants, not theme variables, so CSS can't
#    reach them: the cell grid lines rgb(202,202,202) -> rgb(226,227,227)
#    (light grey) and the active cell / selection outline rgb(72,121,92) ->
#    rgb(0,157,81) (the Drylab accent). The headers are themed in drylab.css.
#
# 2. web-apps/apps/spreadsheeteditor/main/app/controller/Main.js, commit the
#    cell being typed on `blurFocus`. A cell the user is still typing in
#    (no Enter yet) lives only in the cell editor: the document is not
#    "modified", so a forcesave answers "no changes" and the text is lost
#    when the user saves from outside the frame (the integrator's Save /
#    back arrow) and leaves. The public api already has
#    `docEditor.blurFocus()`, but the full editor never listens to it (only
#    the embed viewer does). This adds one listener: on blurFocus, close the
#    cell editor the way clicking another cell does (asc_closeCellEditor,
#    which keeps the text). The integrator calls blurFocus() right before a
#    save the user asked for; nothing else changes.
#
# The image's start-up script regenerates the .gz copies nginx serves and
# flushes the cache, so no stale stock copy is served.
set -euo pipefail
DS="${1:?documentserver dir}"
DATE="${2:?modified date}"
SRC="https://github.com/Drylab-AI/drylab-onlyoffice"

patch() { # <file> <old> <new> <what>
  python3 - "$@" "$DATE" "$SRC" <<'PY'
import sys
path, old, new, what, date, src = sys.argv[1:7]
s = open(path, encoding="utf-8").read()
if s.count(new) == 1 and s.count(old) == 0:
    print(f"already patched: {path}")
    sys.exit(0)
n = s.count(old)
if n != 1:
    sys.exit(f"patch-js: expected the {what} pattern once in {path}, found {n}")
head = f"/* Modified by Drylab on {date}: {what}. Based on ONLYOFFICE Docs by Ascensio System SIA, AGPL v3 + additional terms. Source: {src} */\n"
open(path, "w", encoding="utf-8").write(head + s.replace(old, new))
print(f"patched: {path}")
PY
  [ -f "$1.gz" ] && gzip -kf9 "$1"
  return 0
}

SDK="$DS/sdkjs/cell/sdk-all.js"
[ -f "$SDK" ] || { echo "missing $SDK" >&2; exit 1; }
patch "$SDK" \
  "border:new r(202,202,202)},padding:-1};this.TXa=new r(72,121,92);" \
  "border:new r(226,227,227)},padding:-1};this.TXa=new r(0,157,81);" \
  "spreadsheet grid line and selection colours (2 constants)"

MAIN="$DS/web-apps/apps/spreadsheeteditor/main/app/controller/Main.js"
[ -f "$MAIN" ] || { echo "missing $MAIN" >&2; exit 1; }
patch "$MAIN" \
  "Common.Gateway.on('grabfocus',      _.bind(this.onGrabFocus, this));" \
  "Common.Gateway.on('grabfocus',      _.bind(this.onGrabFocus, this));
                // Drylab: blurFocus() commits the cell being typed (see patch-js.sh).
                Common.Gateway.on('blurfocus',      _.bind(function() { this.api && this.api.isCellEdited && this.api.asc_closeCellEditor(); }, this));" \
  "blurFocus commits the cell being typed (1 listener)"

grep -q "this.TXa=new r(0,157,81);" "$SDK" || { echo "patch-js: grid check failed" >&2; exit 1; }
grep -q "Common.Gateway.on('blurfocus'" "$MAIN" || { echo "patch-js: blurfocus check failed" >&2; exit 1; }
exit 0
