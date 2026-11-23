#!/usr/bin/env bash
# Link the Drylab theme from each editor's main index.html (build step).
# Usage: patch-index.sh <web-apps/apps dir> <modified date>
# Idempotent: an index.html that already links drylab.css is left alone.
set -euo pipefail
APPS="${1:?web-apps apps dir}"
DATE="${2:?modified date}"
CSS="../../common/main/resources/drylab/drylab.css"

for editor in documenteditor spreadsheeteditor presentationeditor; do
  f="$APPS/$editor/main/index.html"
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
  if grep -q 'drylab/drylab.css' "$f"; then
    echo "already patched: $f"
    continue
  fi
  # A blocking stylesheet in <head>: the editor reads theme variables
  # (canvas colours, status bar height) while app.js starts.
  tag="<!-- Modified by Drylab on ${DATE}: Drylab theme (CSS only). Based on ONLYOFFICE Docs by Ascensio System SIA, AGPL v3 + additional terms. Source: https://github.com/Drylab-AI/drylab-onlyoffice --><link rel=\"stylesheet\" type=\"text/css\" href=\"${CSS}\" data-drylab-theme=\"1\"/>"
  # Insert before the first </head> only.
  python3 - "$f" "$tag" <<'PY'
import sys
path, tag = sys.argv[1], sys.argv[2]
html = open(path, encoding="utf-8").read()
i = html.find("</head>")
if i < 0:
    sys.exit(f"no </head> in {path}")
open(path, "w", encoding="utf-8").write(html[:i] + "    " + tag + "\r\n" + html[i:])
PY
  grep -q 'drylab/drylab.css' "$f" || { echo "patch failed: $f" >&2; exit 1; }
  # nginx may serve index.html.gz (gzip_static); keep it in step.
  [ -f "$f.gz" ] && gzip -kf9 "$f"
  echo "patched: $f"
done

# Precompressed copy of the theme too, if the image ships .gz files at all.
for css in "$APPS"/common/main/resources/drylab/*.css; do
  if ls "$APPS"/common/main/resources/css/*.gz >/dev/null 2>&1 || ls "$APPS"/documenteditor/main/resources/css/*.gz >/dev/null 2>&1; then
    gzip -kf9 "$css"
  fi
done
