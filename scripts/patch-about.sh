#!/usr/bin/env bash
# About button at the bottom of the left strip (build step).
# Usage: patch-about.sh <web-apps/apps dir> <modified date>
#
# Why: the legal notice moved from a line in the integrator's header into
# ONE "About" (i) icon pinned to the bottom of ONLYOFFICE's left strip, in
# the document, spreadsheet and presentation editors. Clicking it does not
# open ONLYOFFICE's own About panel (its entry stays hidden):
# it asks the integrator to show its About dialog, through the public
# Gateway's internalMessage, i.e. one
#   window.parent.postMessage('{"event":"onInternalMessage",
#     "data":{"type":"drylab:about","data":{}},"frameEditorId":...}')
# The integrator (Drylab frontend) accepts it only from the
# DocServer's origin, for its own frameEditorId, with exactly that shape.
#
# Two edits per editor, each must find its anchor exactly once or the build
# fails (an ONLYOFFICE update that moves the code can't ship half-patched):
#   1. main/app/template/LeftMenu.template: one <button> before the strip's
#      "more" slot, with the modified-file comment beside it;
#   2. main/app/view/LeftMenu.js: turn it into a Common.UI.Button (hint =
#      ONLYOFFICE's own localized "About") whose click posts the message.
# drylab.css pins it to the bottom of the strip.
set -euo pipefail
APPS="${1:?web-apps apps dir}"
DATE="${2:?modified date}"
SRC="https://github.com/Drylab-AI/drylab-onlyoffice"
WHAT="About button at the bottom of the left strip, opens the integrator's About dialog"

edit() { # <file> <comment style: html|js> <anchor> <replacement>
  python3 - "$@" "$DATE" "$SRC" "$WHAT" <<'PY'
import sys
path, style, old, new, date, src, what = sys.argv[1:8]
s = open(path, encoding="utf-8").read()
if "left-btn-drylab-about" in s:
    print(f"already patched: {path}")
    sys.exit(0)
n = s.count(old)
if n != 1:
    sys.exit(f"patch-about: expected the anchor once in {path}, found {n}")
note = f"Modified by Drylab on {date}: {what}. Based on ONLYOFFICE Docs by Ascensio System SIA, AGPL v3 + additional terms. Source: {src}"
# Templates are parsed into jQuery markup: a comment before the root
# element would become a stray node, so there it goes next to the button.
if style == "html":
    out = s.replace(old, f"<!-- {note} -->" + new)
else:
    out = f"/* {note} */\n" + s.replace(old, new)
open(path, "w", encoding="utf-8").write(out)
print(f"patched: {path}")
PY
  [ -f "$1.gz" ] && gzip -kf9 "$1"
  return 0
}

BTN='<button id="left-btn-drylab-about" class="btn btn-category" content-target="" data-hint="0" data-hint-direction="right" data-hint-offset="big"><i class="icon toolbar__icon btn-menu-about" aria-hidden="true">&nbsp;</i></button>'
JS="// Drylab: About button (scripts/patch-about.sh). Asks the integrator to show its About dialog.
            this.btnDrylabAbout = new Common.UI.Button({
                el: \$markup.elementById('#left-btn-drylab-about'),
                hint: this.tipAbout
            });
            this.btnDrylabAbout.cmpEl.attr('aria-label', this.tipAbout);
            this.btnDrylabAbout.on('click', function () {
                Common.Gateway.internalMessage('drylab:about', {});
            });

            this.\$el.html(\$markup);"

for editor in documenteditor spreadsheeteditor presentationeditor; do
  tpl="$APPS/$editor/main/app/template/LeftMenu.template"
  view="$APPS/$editor/main/app/view/LeftMenu.js"
  [ -f "$tpl" ] && [ -f "$view" ] || { echo "missing $tpl or $view" >&2; exit 1; }
  edit "$tpl" html '<div id="slot-left-menu-more"></div>' "${BTN}<div id=\"slot-left-menu-more\"></div>"
  edit "$view" js 'this.$el.html($markup);' "$JS"
  grep -q 'id="left-btn-drylab-about"' "$tpl" || { echo "patch-about: template check failed ($editor)" >&2; exit 1; }
  grep -q "internalMessage('drylab:about'" "$view" || { echo "patch-about: view check failed ($editor)" >&2; exit 1; }
done
exit 0
