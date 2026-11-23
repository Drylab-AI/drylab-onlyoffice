# drylab-onlyoffice

Drylab's modified build of ONLYOFFICE Docs Community 10.0.0.1: the upstream image `onlyoffice/documentserver:10.0.0.1` plus one CSS theme. Based on ONLYOFFICE Docs by Ascensio System SIA. ONLYOFFICE is a trademark of Ascensio System SIA; this build is not an official ONLYOFFICE product.

Licence: GNU AGPL v3 with the ONLYOFFICE additional terms (`LICENSE`, `NOTICE`). Anyone who uses this build over a network is entitled to this source.

## What it changes

CSS only, in web-apps (details and dates in `NOTICE`):

- `drylab-theme/drylab.css`: a light, flat look for the "White" interface theme. It gives a white header row, tabs as plain text menu items with a soft hover, the toolbar as one rounded light pill, a soft blue-grey canvas (`#F0F4F9`) around the page, a 28 px status bar and Drylab green as the accent.
- The ONLYOFFICE logo stays visible: smaller (70 px) and muted (60 % opacity, full on hover), never hidden or covered.
- The About panel keeps all of ONLYOFFICE's text and adds a line saying this build is modified, by Drylab, on 2026-11-23, based on ONLYOFFICE Docs, with the licence and this repository's URL.
- `scripts/patch-index.sh` (run by the `Dockerfile`) adds one `<link>` with a "Modified by Drylab" comment to the document, spreadsheet and presentation editors' `index.html`. The image's start-up script regenerates the gzip copies nginx serves (`gzip_static on`) from the patched files.

The theme applies only when the integrator selects `customization.uiTheme: "theme-white"`, as the Drylab backend does. The other themes stay stock.

## Build and run (local only)

```bash
docker build -t drylab-onlyoffice:local .
docker run -d --name drylab-oo -p 127.0.0.1:8085:80 --add-host host.docker.internal:host-gateway \
  -e JWT_ENABLED=true -e JWT_SECRET=<secret> -e JWT_HEADER=AuthorizationJwt -e JWT_IN_BODY=true \
  -e ALLOW_PRIVATE_IP_ADDRESS=true -e WOPI_ENABLED=false drylab-onlyoffice:local
```

These are the environment variables an integration needs (JWT in a custom header and in the body, private callback addresses allowed, WOPI off). Wait for `curl 127.0.0.1:8085/healthcheck` to return `true`, then about 30 s more while start-up regenerates the gzip copies.

## Verify

```bash
JWT_SECRET=<32+ chars> scripts/verify.sh             # static checks (curl)
JWT_SECRET=<32+ chars> scripts/verify.sh --browser   # + harness and headless screenshots
```

The static checks are:

- each editor's `index.html` (plain and gzip) links the theme and carries the modified notice;
- the theme is served and has the About notice;
- no rule hides the logo (the check fails if one sets display none, visibility hidden, zero size or opacity below 0.4);
- `LICENSE` matches the image's `LICENSE.txt`;
- `NOTICE` ships in the image.

`--browser` starts `scripts/harness.py`, a stand-in for the Drylab backend that signs configs and receives saves. It opens a docx, an xlsx and a pptx in headless `agent-browser`, and asserts the theme is applied and the logo is visible and not covered. It saves the screenshots and DOM facts to `scripts/out/evidence/`. The test browser runs with `--disable-web-security` only so `probe.js` can read the DocServer iframe.

Manual checks used for the first release (2026-11-23), all on 127.0.0.1:

- type in each format, then forcesave: the callback file contains the edit;
- `downloadAs('pdf')` returns a PDF;
- Insert > Image > Image from storage, signed `insertImage`;
- File > Rename and File > Version History (with the integrator events wired);
- About shows the Ascensio System SIA details plus the modified notice.

## Updating ONLYOFFICE

Bump the `FROM` tag, and re-check the selectors in `drylab.css` against the new web-apps (`#toolbar .tabs`, `.box-controls`, `#header-logo`, `#about-menu-panel`). Update the date in `NOTICE`, `Dockerfile`, `drylab.css` and the About text, then run `scripts/verify.sh --browser`.
