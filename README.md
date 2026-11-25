# drylab-onlyoffice

A modified build of [ONLYOFFICE Docs](https://github.com/ONLYOFFICE/DocumentServer) Community Edition, the document server developed by Ascensio System SIA. It adds a light theme, a few small interface patches and one spreadsheet save fix on top of the official image `onlyoffice/documentserver:10.0.0.1`.

ONLYOFFICE is a trademark of Ascensio System SIA. This build is not an official ONLYOFFICE product and is not endorsed by Ascensio System SIA.

## Licence

GNU Affero General Public License v3 with the ONLYOFFICE additional terms: see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). This repository is the Corresponding Source of the modified version. Anyone who uses it over a network is entitled to this source.

## Upstream source

The base image `onlyoffice/documentserver:10.0.0.1` (`sha256:ca17889f10b11141cc6441836aebdd2835cf3e1b49681b2fd6e155c94b7850b3`) contains the package `onlyoffice-documentserver 10.0.0-169`, built from:

| Repository | Tag | Commit |
|---|---|---|
| [ONLYOFFICE/web-apps](https://github.com/ONLYOFFICE/web-apps) | `v10.0.0.169` | `493e500c56ec96ccaa0452ab092cbce23b6dcc2e` |
| [ONLYOFFICE/sdkjs](https://github.com/ONLYOFFICE/sdkjs) | `v10.0.0.169` | `3679e0375a758d7dc59d31337a45461be3525ed8` |
| [ONLYOFFICE/server](https://github.com/ONLYOFFICE/server) | `v10.0.0.169` | `f9a8df6e7c9aa388c0d525965923c803f4cbc071` |
| [ONLYOFFICE/core](https://github.com/ONLYOFFICE/core) | `v10.0.0.169` | `76af764fcb777291098c73728044249b6893af6a` |
| [ONLYOFFICE/Docker-DocumentServer](https://github.com/ONLYOFFICE/Docker-DocumentServer) | `v10.0.0.1` | `d59714446cde55a9f814928d1d984a6f43911bd7` |

## What it changes

Only files in `web-apps` and `sdkjs` that are served to the browser. The server, converter and binaries are unchanged. Every changed file carries a "Modified by Drylab" line with the date. `NOTICE` lists each change.

| Change | Files | How |
|---|---|---|
| Light theme for the "White" interface theme: flat header and tabs, one-row toolbar, soft canvas, Sheets/Slides-style grid, formula bar, sheet tabs and notes. The ONLYOFFICE logo stays visible | `drylab-theme/drylab.css`, linked from each editor's `index.html` | `scripts/patch-index.sh` |
| Spreadsheet grid and selection colours | `sdkjs/cell/sdk-all.js` (two constants) | `scripts/patch-js.sh` |
| Spreadsheet save fix: `docEditor.blurFocus()` commits the cell being typed, so a save started by the integrator keeps it | spreadsheet `controller/Main.js` (one listener) | `scripts/patch-js.sh` |
| An "About" button at the bottom of each editor's left strip; it asks the integrator page to show the legal notices | each editor's `LeftMenu.template` and `view/LeftMenu.js` | `scripts/patch-about.sh` |

The theme applies only when the integrator sets `customization.uiTheme: "theme-white"`. Each patch script fails the build when its anchor is not found exactly once, so an ONLYOFFICE update can't ship half-patched.

## Legal notices in the interface

ONLYOFFICE's own About entry in the left strip is hidden. The Drylab "About" button takes its place and opens the integrating application's About dialog, which names ONLYOFFICE Docs by Ascensio System SIA as the original software, states that this is a modified version, and links to the licence and to this source. The ONLYOFFICE logo stays visible in the menu row.

## Build and run

```bash
docker build -t drylab-onlyoffice:<tag> .
docker run -d --name drylab-oo -p 127.0.0.1:8085:80 \
  -e JWT_ENABLED=true -e JWT_SECRET=<secret> -e JWT_HEADER=AuthorizationJwt -e JWT_IN_BODY=true \
  -e ALLOW_PRIVATE_IP_ADDRESS=true -e WOPI_ENABLED=false drylab-onlyoffice:<tag>
```

Wait for `curl 127.0.0.1:8085/healthcheck` to return `true`, then about 30 s more while start-up regenerates the gzip copies. Release tags follow `v10.0.0.1-drylab.<n>`, and the Dockerfile label names the same tag.

## Verify

```bash
JWT_SECRET=<32+ chars> scripts/verify.sh             # static checks
JWT_SECRET=<32+ chars> scripts/verify.sh --browser   # + local harness and headless screenshots
```

The static checks build the image, run it on 127.0.0.1 and confirm that:

- each editor's `index.html` links the theme and carries the modified notice;
- the theme is served, carries the modified-version notice and never hides the ONLYOFFICE logo;
- the spreadsheet patches and the About button are served, each with its modified-file line;
- `LICENSE` matches the image's `LICENSE.txt` and `NOTICE` ships in the image.

`--browser` also starts `scripts/harness.py`, a small stand-in integrator that signs editor configs and receives saves, and checks the theme, the logo, the hidden items and the About button in headless browsers.

## Updating ONLYOFFICE

Bump the `FROM` tag and the upstream table above, then run `scripts/verify.sh --browser`. The patch scripts stop the build if an anchor moved. Re-check the selectors in `drylab.css` against the new web-apps, and update the modification dates in `NOTICE` and the `Dockerfile`.
