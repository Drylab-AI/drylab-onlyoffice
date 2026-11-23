// Sheets / Slides look probe ( test only): DOM facts for the
// formula bar, grid headers, sheet tabs, status bar (xlsx) and the
// thumbnails, canvas and notes (pptx). Prints one JSON object.
(() => {
  const f = document.querySelector('iframe'); const d = f && f.contentDocument;
  if (!d) return JSON.stringify({ error: 'no iframe' });
  const vis = (e) => { if (!e) return false; const r = e.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false; for (let n = e; n && n !== d.body; n = n.parentElement) { const cs = getComputedStyle(n); if (cs.display === 'none' || cs.visibility === 'hidden') return false; } return true; };
  const R = (e) => { if (!e) return null; const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); return { x: Math.round(r.x), y: Math.round(r.y), r: Math.round(r.right), b: Math.round(r.bottom), w: Math.round(r.width), h: Math.round(r.height), bg: cs.backgroundColor, color: cs.color, bt: cs.borderTopWidth + ' ' + cs.borderTopColor, bb: cs.borderBottomWidth + ' ' + cs.borderBottomColor, bl: cs.borderLeftWidth + ' ' + cs.borderLeftColor, br: cs.borderRightWidth + ' ' + cs.borderRightColor, rad: cs.borderRadius, fs: cs.fontSize, fw: cs.fontWeight, sh: cs.boxShadow, vis: vis(e) }; };
  const css = getComputedStyle(d.body); const v = (n) => css.getPropertyValue(n).trim();
  const out = { vw: d.documentElement.clientWidth, sheetCss: !!d.querySelector('link[data-drylab-theme-editor]'), pill: R(d.querySelector('#toolbar .box-controls')), statusbar: R(d.querySelector('.statusbar')), logo: vis(d.getElementById('header-logo')) };
  if (d.querySelector('#ws-canvas')) {
    out.kind = 'xlsx';
    out.formulaBar = R(d.querySelector('#cell-editing-box'));
    out.nameBox = R(d.querySelector('#ce-cell-name'));
    out.fx = R(d.querySelector('#ce-func-label'));
    out.formulaInput = R(d.querySelector('#ce-cell-content'));
    out.grid = R(d.querySelector('#ws-canvas'));
    out.headerVars = { bg: v('--canvas-cell-title-background'), border: v('--canvas-cell-title-border'), text: v('--canvas-cell-title-text'), selBg: v('--canvas-cell-title-background-selected'), selBorder: v('--canvas-cell-title-border-selected'), hover: v('--canvas-cell-title-background-hover') };
    out.addSheet = R(d.querySelector('#status-btn-addtab'));
    out.tabs = [...d.querySelectorAll('#status-sheets-bar .nav-tabs > li')].filter(vis).map((li) => ({ active: li.classList.contains('active'), t: li.innerText.trim(), ...R(li.querySelector('span')) }));
    out.math = R(d.querySelector('#status-math-box'));
    out.zoom = R(d.querySelector('#status-zoom-box'));
    out.gapPillToFormula = out.formulaBar && out.pill ? out.formulaBar.y - out.pill.b : null;
  }
  if (d.querySelector('#id_panel_thumbnails')) {
    out.kind = 'pptx';
    out.thumbs = R(d.querySelector('#id_panel_thumbnails'));
    out.thumbsCanvasBg = v('--canvas-background');
    out.previewSelect = v('--border-preview-select');
    out.main = R(d.querySelector('#id_main'));
    out.view = R(d.querySelector('#id_main_view'));
    out.notes = R(d.querySelector('#id_panel_notes'));
    out.slideshow = R(d.querySelector('#slot-status-btn-preview'));
    out.slideLabel = R(d.querySelector('#status-label-pages'));
  }
  return JSON.stringify(out);
})()
