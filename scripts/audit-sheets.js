// Google Sheets / Slides look audit ( test only). Run with
// agent-browser eval in a --disable-web-security browser on the harness
// page. Prints {kind, vw, issues[]}; issues is empty when the look holds.
(() => {
  const f = document.querySelector('iframe'); const d = f && f.contentDocument;
  if (!d) return JSON.stringify({ error: 'no iframe document' });
  const vis = (e) => { if (!e) return false; const r = e.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false; for (let n = e; n && n !== d.body; n = n.parentElement) { const cs = getComputedStyle(n); if (cs.display === 'none' || cs.visibility === 'hidden') return false; } return true; };
  const R = (e) => e.getBoundingClientRect();
  const css = getComputedStyle(d.body); const v = (n) => css.getPropertyValue(n).trim().toUpperCase();
  const vw = d.documentElement.clientWidth; const issues = []; let kind = null;
  const pill = d.querySelector('#toolbar .box-controls');
  if (!vis(d.getElementById('header-logo'))) issues.push('logo not visible');
  if (d.querySelector('#ws-canvas')) {
    kind = 'xlsx';
    const fb = d.querySelector('#cell-editing-box'), nb = d.querySelector('#ce-cell-name'), fx = d.querySelector('#ce-func-label'), inp = d.querySelector('#ce-cell-content');
    if (!vis(fb) || !vis(nb) || !vis(fx) || !vis(inp)) issues.push('formula bar part hidden');
    else {
      const gap = R(fb).top - R(pill).bottom;
      if (gap > 6) issues.push(`formula bar ${Math.round(gap)} px below the pill (want <= 6)`);
      if (!(R(nb).right <= R(fx).left + 1 && R(fx).right <= R(inp).left + 1)) issues.push('formula bar order is not name box, fx, input');
      if (getComputedStyle(fb).backgroundColor !== 'rgb(255, 255, 255)') issues.push('formula bar not white');
      if (getComputedStyle(fx, '::after').content !== '"fx"') issues.push('fx label missing');
      if (R(inp).right > vw + 1) issues.push('formula input clipped');
    }
    if (v('--canvas-cell-title-background-selected') !== '#D3EEE1') issues.push('selected header not accent-tinted');
    if (v('--canvas-cell-title-background') !== '#F8F9FA') issues.push('header background not light grey');
    if (!vis(d.querySelector('#status-btn-addtab'))) issues.push('add-sheet button hidden');
    const tabs = [...d.querySelectorAll('#status-sheets-bar .nav-tabs > li')].filter(vis);
    const act = tabs.find((t) => t.classList.contains('active'));
    if (!act) issues.push('no active sheet tab');
    else {
      const s = getComputedStyle(act.querySelector('span'));
      if (s.backgroundColor !== 'rgb(230, 245, 238)') issues.push(`active tab bg ${s.backgroundColor}`);
      if (s.boxShadow !== 'none') issues.push('active tab still has the stock inset bar');
      const sb = R(d.querySelector('.statusbar')); const ar = R(act.querySelector('span'));
      if (ar.top < sb.top - 1 || ar.bottom > sb.bottom + 1) issues.push('active tab outside the status bar');
    }
    const zoom = d.querySelector('#status-zoom-box');
    if (vis(zoom) && R(zoom).right > vw + 1) issues.push('zoom clipped');
  }
  if (d.querySelector('#id_panel_thumbnails')) {
    kind = 'pptx';
    const th = d.querySelector('#id_panel_thumbnails');
    if (!vis(th)) issues.push('thumbnails hidden');
    else if (getComputedStyle(th).backgroundColor !== 'rgb(255, 255, 255)') issues.push('thumbnails not white');
    if (v('--border-preview-select') !== '#009D51') issues.push('selected thumbnail not accent');
    const notes = d.querySelector('#id_panel_notes');
    if (vis(notes)) {
      if (getComputedStyle(notes).backgroundColor !== 'rgb(255, 255, 255)') issues.push('notes not white');
      if (R(notes).height > 90) issues.push(`notes not slim (${Math.round(R(notes).height)} px)`);
    }
    const view = d.querySelector('#id_main_view'); const main = d.querySelector('#id_main');
    if (vis(view) && vis(main) && getComputedStyle(main).backgroundColor !== 'rgb(240, 244, 249)') issues.push('slide canvas background not light');
    if (!vis(d.querySelector('#slot-status-btn-preview'))) issues.push('slideshow button hidden');
  }
  return JSON.stringify({ kind, vw, issues });
})()
