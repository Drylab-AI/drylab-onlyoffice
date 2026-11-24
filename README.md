# drylab-onlyoffice

Drylab's modified build of ONLYOFFICE Docs Community 10.0.0.1 (current tag `10.0.0.1-drylab.5`, spreadsheet / presentation look of 2026-11-24): the upstream image `onlyoffice/documentserver:10.0.0.1` plus one CSS theme and, since `drylab.5`, two spreadsheet grid colour constants. Based on ONLYOFFICE Docs by Ascensio System SIA. ONLYOFFICE is a trademark of Ascensio System SIA; this build is not an official ONLYOFFICE product.

Licence: GNU AGPL v3 with the ONLYOFFICE additional terms (`LICENSE`, `NOTICE`). Anyone who uses this build over a network is entitled to this source.

## What it changes

CSS only, in web-apps (details and dates in `NOTICE`):

- `drylab-theme/drylab.css`: a light, flat look for the "White" interface theme. It gives a white header row, tabs as plain text menu items with a soft hover, the toolbar as one rounded light pill, a soft blue-grey canvas (`#F0F4F9`) around the page, a 28 px status bar and Drylab green as the accent.
- The ONLYOFFICE logo stays visible: smaller (70 px) and muted (60 % opacity, full on hover), never hidden or covered.
- The About panel keeps all of ONLYOFFICE's text and adds a line saying this build is modified, by Drylab, based on ONLYOFFICE Docs, with the licence and this repository's URL. Since `drylab.3` its left-strip entry is hidden; see "Legal notices" below.
- `scripts/patch-index.sh` (run by the `Dockerfile`) adds one `<link>` with a "Modified by Drylab" comment to the document, spreadsheet and presentation editors' `index.html`. The image's start-up script regenerates the gzip copies nginx serves (`gzip_static on`) from the patched files.

The theme applies only when the integrator selects `customization.uiTheme: "theme-white"`, as the Drylab backend does. The other themes stay stock.

### Layout v2 (2026-11-23, `10.0.0.1-drylab.2`)

- The menu row reads as the second line of the integrator's header: plain 14 px items whose first text starts at the integrator's title x (`--drylab-menu-indent`, 93 px; 57 px below 640 px), the ONLYOFFICE logo at the far right of that row (visible, muted).
- No duplicate header items: ONLYOFFICE's avatar, header search and header Share are hidden.
- One-row toolbar pill (40 px, radius 24 px, `#EEF3F1`): the two stacked button rows sit side by side, tall buttons are icon-only, and the style gallery shows only the current style plus its full dropdown. ONLYOFFICE's own "more" menu keeps whatever does not fit, so every function stays reachable.
- 26 px status bar; page border `#D5DBE3` on the `#F0F4F9` canvas.
- Not changed by CSS: comments, chat and version history are turned off by the integrator's config (`permissions.comment/chat: false`, no history events); rulers come from `customization.hideRulers: false`. The side-strip About button stays: in 10.0.0.1 it is the only entry to the About panel with the legal notices.

### Polish (2026-11-24, `10.0.0.1-drylab.3`)

- Toolbar row fixed for captioned tabs (View > Zoom, Layout indents and spacing, presentation galleries, Animation's two-line buttons): everything sits inside the 40 px pill and ONLYOFFICE's own "more" menu still collects what does not fit. Checked on every tab of docx, xlsx and pptx at 1024, 1280, 1366, 1440, 1704, 1920 and 390 px with `scripts/sweep.sh` + `scripts/audit.js`.
- Menu row items 13 px.
- Hidden by CSS (no Community config key): the Collaboration tab, the users counter, the Editing/Viewing switch, the header close button, the left-strip About entry.
- Removed by the integrator's config: the Protection tab (`document.permissions.protect: false`); comments, track changes and chat stay off (`permissions.comment/review/chat: false`). Co-editing is unchanged.

### Round 4 (2026-11-24, `10.0.0.1-drylab.4`)

- No new hiding CSS. ONLYOFFICE's File > "Suggest a Feature" is removed by the integrator's config (`customization.suggestFeature: false`); "Feedback & Support" and Help were already off (`feedback: false`, `help: false`). `verify.sh --browser` checks all three stay hidden.
- Comments in `drylab.css`, `NOTICE` ("Where the legal notices are shown"), this README and `verify.sh` follow the integrator's new notice line.
- `scripts/harness.py`: `bar=v4` mock (no save icon, no (i), 16 px file icon, the notice line) and `suggestFeature: false` in its customization.

### Spreadsheet and presentation look (2026-11-24, `10.0.0.1-drylab.5`)

Reference: a light, Sheets/Slides-style editor in Drylab colours.

- Spreadsheet (CSS): column letters / row numbers light grey (`#F8F9FA`, hairline `#E1E3E6`), the selected header tinted green (`#D3EEE1`), via ONLYOFFICE's own `--canvas-cell-title-*` theme variables. Formula bar as one white line directly under the pill: cell name, an "fx" label (the function button keeps its tooltip and action), the input. Sheet tabs flat and rounded, the active one tinted green; "+" and the sheet list stay first. Selection stats (Sum, Count, Average...) muted on the right, before zoom.
- Spreadsheet (sdkjs): the grid line and active-cell outline colours are constants in `sdkjs/cell/sdk-all.js`, not variables. `scripts/patch-js.sh` changes exactly those two (grid `202,202,202` -> `226,227,227`, selection `72,121,92` -> `0,157,81`) and adds a modified-file line; the build fails if they are not found exactly once.
- Spreadsheet (fix): a cell still being typed in (no Enter yet) was lost when the user saved from the Drylab bar and left: ONLYOFFICE keeps it in the cell editor, the document is not "modified", forcesave answers "no changes". The public `docEditor.blurFocus()` reaches the frame but the full editor ignored it (only the embed viewer listens). `patch-js.sh` adds one listener in the spreadsheet editor's `Main.js`: on blurFocus, close the cell editor the way clicking another cell does (the text is kept). The Drylab frontend calls `blurFocus()` before every save it starts.
- Presentation (CSS): thumbnails stay white with the green outline on the selected slide (`--border-preview-select`), a hairline beside them; the speaker-notes strip under the slide is white (it was the canvas grey), slim, hairline above. Slideshow stays in the status bar and in ONLYOFFICE's own menus.
- Checks: `scripts/audit-sheets.js` (look audit, run by `sweep.sh` per file and width and by `verify.sh --browser`), `scripts/sheets-probe.js` (DOM facts), `scripts/readback.py` (openpyxl / python-pptx read-back of a saved file).

## Legal notices

ONLYOFFICE's in-editor About entry is hidden since `drylab.3`. Since `drylab.4` the Drylab app shows one muted line outside the editor frame, "Based on the open-source ONLYOFFICE Docs (AGPL v3)" (trademark sentence in its tooltip): at the right end of the bar above the editor from 1024 px wide, as a thin line under the editor below that, in en/vi/ja/zh. `NOTICE` has the complete notices. Inside the editor the ONLYOFFICE logo stays visible and File > Info still opens.

## Build and run (local only)

```bash
docker build -t drylab-onlyoffice:10.0.0.1-drylab.5 .
docker run -d --name drylab-oo -p 127.0.0.1:8085:80 --add-host host.docker.internal:host-gateway \
  -e JWT_ENABLED=true -e JWT_SECRET=<secret> -e JWT_HEADER=AuthorizationJwt -e JWT_IN_BODY=true \
  -e ALLOW_PRIVATE_IP_ADDRESS=true -e WOPI_ENABLED=false drylab-onlyoffice:10.0.0.1-drylab.5
```

These are the environment variables an integration needs (JWT in a custom header and in the body, private callback addresses allowed, WOPI off). Wait for `curl 127.0.0.1:8085/healthcheck` to return `true`, then about 30 s more while start-up regenerates the gzip copies.

## Build

Build the image with `docker build -t drylab-onlyoffice:<tag> .` (see "Build and run" above) and check it with `scripts/verify.sh`. Release tags follow `v10.0.0.1-drylab.<n>`; the Dockerfile label names the same tag.

## Verify

```bash
JWT_SECRET=<32+ chars> scripts/verify.sh             # static checks (curl)
JWT_SECRET=<32+ chars> scripts/verify.sh --browser   # + harness and headless screenshots
```

The static checks are:

- each editor's `index.html` (plain and gzip) links the theme and carries the modified notice;
- the theme is served and has the modified-version notice;
- no rule hides the logo (the check fails if one sets display none, visibility hidden, zero size or opacity below 0.4);
- `NOTICE` says where the integrator's notice line is shown and carries the complete notices;
- the served `sdkjs/cell/sdk-all.js` (plain and gzip) has the two Drylab grid colours, not the stock ones, and the spreadsheet `Main.js` the blurFocus listener, each with its modified-file line;
- `LICENSE` matches the image's `LICENSE.txt`;
- `NOTICE` ships in the image.

`--browser` starts `scripts/harness.py`, a stand-in for the Drylab backend that signs configs and receives saves. It opens a docx, an xlsx and a pptx in headless `agent-browser`, and asserts the theme is applied, the logo is visible and not covered, File > Info opens, and the hidden items (About entry, Collaboration and Protection tabs, users counter, mode switch, close button, and with the integrator's config Feedback & Support, Help and Suggest a Feature) stay hidden. It saves the screenshots and DOM facts to `scripts/out/evidence/`. The test browser runs with `--disable-web-security` only so `probe.js` can read the DocServer iframe.

Manual checks used for the first release (2026-11-23), all on 127.0.0.1:

- type in each format, then forcesave: the callback file contains the edit;
- `downloadAs('pdf')` returns a PDF;
- Insert > Image > Image from storage, signed `insertImage`;
- File > Rename (with the integrator event wired); File > Version History absent once the integrator drops the history events (layout v2);
- About shows the Ascensio System SIA details plus the modified notice (until drylab.2; drylab.3 the integrator's (i) dialog; since drylab.4 the integrator's notice line).

Responsive sweep (drylab.3): `scripts/sweep.sh <out> <prefix>` with the harness running opens each fixture at each width, clicks every visible tab, screenshots it and runs `scripts/audit.js` (wrapped captions, controls outside the pill, overlaps, clipped text, hidden items shown). Since drylab.5 it also runs `scripts/audit-sheets.js` once per xlsx/pptx and width (`<prefix>-look.jsonl`). The harness takes `DS_CB_HOST` when the DocServer is not on port 8085.

## Updating ONLYOFFICE

Bump the `FROM` tag, and re-check the selectors in `drylab.css` against the new web-apps (`#toolbar .tabs`, `.box-controls`, `.elset`, `.x-huge`, `#slot-field-styles`, `.more-box`, `#box-right-btn-group`, `#header-logo`, `#about-menu-panel`, `#left-btn-about`, `#slot-btn-edit-mode`, `#tlb-box-users`, `#slot-btn-close`, `toolbar-collaboration`, `.slot-lbl-zoom`, `.combo-dataview`, `#cell-editing-box`, `#ce-func-label`, `#status-sheets-bar`, `#id_panel_notes`), check that `scripts/patch-js.sh` still finds its grid constants and the `grabfocus` line it extends (the build fails if not). Update the date in `NOTICE`, `Dockerfile`, `drylab.css` and the About text, then run `scripts/verify.sh --browser`.
