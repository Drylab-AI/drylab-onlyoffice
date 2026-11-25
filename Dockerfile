# Drylab build of ONLYOFFICE Docs Community: the official image plus a light
# theme, small interface patches and one spreadsheet save fix.
#
# MODIFIED VERSION NOTICE: modified by Drylab (Drylab-AI) on 2026-11-23 and
# 2026-11-24. Based on ONLYOFFICE Docs by Ascensio System SIA
# (onlyoffice/documentserver:10.0.0.1, package 10.0.0-169), GNU AGPL v3
# with additional terms. What changed and the exact upstream revisions:
# see NOTICE.
#
# Build steps (no server or binary change):
#   1. scripts/patch-index.sh: adds drylab.css and links it from the
#      document, spreadsheet and presentation editors' index.html;
#   2. scripts/patch-js.sh: two spreadsheet grid colour constants in
#      sdkjs/cell/sdk-all.js and one blurFocus listener in the spreadsheet
#      controller/Main.js;
#   3. scripts/patch-about.sh: an About button in each editor's left strip;
#   4. regenerates the precompressed (.gz) copies of the touched files, so
#      nginx never serves a stale stock copy when gzip_static is on.
FROM onlyoffice/documentserver:10.0.0.1

ARG WEBAPPS=/var/www/onlyoffice/documentserver/web-apps/apps
ARG DRYLAB_MODIFIED_DATE=2026-11-24

LABEL org.opencontainers.image.title="drylab-onlyoffice" \
      org.opencontainers.image.description="Modified ONLYOFFICE Docs Community 10.0.0.1 by Drylab (theme, interface patches, spreadsheet save fix; tag 10.0.0.1-drylab.6). Based on ONLYOFFICE Docs by Ascensio System SIA." \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Drylab-AI/drylab-onlyoffice" \
      org.opencontainers.image.base.name="onlyoffice/documentserver:10.0.0.1"

COPY drylab-theme/ ${WEBAPPS}/common/main/resources/drylab/
COPY NOTICE /var/www/onlyoffice/documentserver/DRYLAB-NOTICE.txt
COPY scripts/patch-index.sh /tmp/patch-index.sh
COPY scripts/patch-js.sh /tmp/patch-js.sh
COPY scripts/patch-about.sh /tmp/patch-about.sh

RUN bash /tmp/patch-index.sh "${WEBAPPS}" "${DRYLAB_MODIFIED_DATE}" \
 && bash /tmp/patch-js.sh /var/www/onlyoffice/documentserver "${DRYLAB_MODIFIED_DATE}" \
 && bash /tmp/patch-about.sh "${WEBAPPS}" "${DRYLAB_MODIFIED_DATE}" \
 && rm /tmp/patch-index.sh /tmp/patch-js.sh /tmp/patch-about.sh \
 && chown -R ds:ds ${WEBAPPS}/common/main/resources/drylab
