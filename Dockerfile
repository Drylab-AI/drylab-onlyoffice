# Drylab build of ONLYOFFICE Docs Community: upstream image + a CSS theme
# (and, since drylab.5, two small spreadsheet JS changes).
#
# MODIFIED VERSION NOTICE: modified by Drylab (Drylab-AI) on 2026-11-23
# (theme, drylab.1), 2026-11-23 (layout v2, drylab.2), 2026-11-24
# (polish, drylab.3), 2026-11-24 (notice line docs, drylab.4) and
# 2026-11-24 (spreadsheet / presentation look, drylab.5).
# Based on ONLYOFFICE Docs by Ascensio System SIA (onlyoffice/documentserver
# 10.0.0.1), GNU AGPL v3 with additional terms. What changed: see NOTICE.
#
# Changes (no server or binary change):
#   1. adds web-apps/apps/common/main/resources/drylab/drylab.css;
#   2. links it from the main index.html of the document, spreadsheet and
#      presentation editors, with a "modified by Drylab" comment;
#   3. (drylab.5) scripts/patch-js.sh: sdkjs/cell/sdk-all.js, two colour
#      constants of the spreadsheet grid (grid lines, active-cell outline);
#      spreadsheeteditor Main.js, one listener so blurFocus() commits the
#      cell being typed. Each file gets a "modified by Drylab" header line;
#   4. regenerates any precompressed (.gz) copy of the touched files, so
#      nginx never serves a stale stock copy when gzip_static is on.
FROM onlyoffice/documentserver:10.0.0.1

ARG WEBAPPS=/var/www/onlyoffice/documentserver/web-apps/apps
ARG DRYLAB_MODIFIED_DATE=2026-11-24

LABEL org.opencontainers.image.title="drylab-onlyoffice" \
      org.opencontainers.image.description="Modified ONLYOFFICE Docs Community 10.0.0.1 (CSS restyle, layout v2, polish, round 4 and spreadsheet / presentation look by Drylab, tag 10.0.0.1-drylab.5). Based on ONLYOFFICE Docs by Ascensio System SIA." \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Drylab-AI/drylab-onlyoffice" \
      org.opencontainers.image.base.name="onlyoffice/documentserver:10.0.0.1"

COPY drylab-theme/ ${WEBAPPS}/common/main/resources/drylab/
COPY NOTICE /var/www/onlyoffice/documentserver/DRYLAB-NOTICE.txt
COPY scripts/patch-index.sh /tmp/patch-index.sh
COPY scripts/patch-js.sh /tmp/patch-js.sh

RUN bash /tmp/patch-index.sh "${WEBAPPS}" "${DRYLAB_MODIFIED_DATE}" \
 && bash /tmp/patch-js.sh /var/www/onlyoffice/documentserver "${DRYLAB_MODIFIED_DATE}" \
 && rm /tmp/patch-index.sh /tmp/patch-js.sh \
 && chown -R ds:ds ${WEBAPPS}/common/main/resources/drylab
