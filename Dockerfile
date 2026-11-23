# Drylab build of ONLYOFFICE Docs Community: upstream image + a CSS theme.
#
# MODIFIED VERSION NOTICE: modified by Drylab (Drylab-AI) on 2026-11-23
# (theme, drylab.1), 2026-11-23 (layout v2, drylab.2), 2026-11-24
# (polish, drylab.3) and 2026-11-24 (notice line docs, drylab.4).
# Based on ONLYOFFICE Docs by Ascensio System SIA (onlyoffice/documentserver
# 10.0.0.1), GNU AGPL v3 with additional terms. What changed: see NOTICE.
#
# Changes, all in web-apps (no server, sdkjs or binary change):
#   1. adds web-apps/apps/common/main/resources/drylab/drylab.css;
#   2. links it from the main index.html of the document, spreadsheet and
#      presentation editors, with a "modified by Drylab" comment;
#   3. regenerates any precompressed (.gz) copy of the touched files, so
#      nginx never serves a stale stock copy when gzip_static is on.
FROM onlyoffice/documentserver:10.0.0.1

ARG WEBAPPS=/var/www/onlyoffice/documentserver/web-apps/apps
ARG DRYLAB_MODIFIED_DATE=2026-11-24

LABEL org.opencontainers.image.title="drylab-onlyoffice" \
      org.opencontainers.image.description="Modified ONLYOFFICE Docs Community 10.0.0.1 (CSS restyle, layout v2, polish and round 4 by Drylab, tag 10.0.0.1-drylab.4). Based on ONLYOFFICE Docs by Ascensio System SIA." \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Drylab-AI/drylab-onlyoffice" \
      org.opencontainers.image.base.name="onlyoffice/documentserver:10.0.0.1"

COPY drylab-theme/ ${WEBAPPS}/common/main/resources/drylab/
COPY NOTICE /var/www/onlyoffice/documentserver/DRYLAB-NOTICE.txt
COPY scripts/patch-index.sh /tmp/patch-index.sh

RUN bash /tmp/patch-index.sh "${WEBAPPS}" "${DRYLAB_MODIFIED_DATE}" \
 && rm /tmp/patch-index.sh \
 && chown -R ds:ds ${WEBAPPS}/common/main/resources/drylab
