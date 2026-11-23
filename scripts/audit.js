// Responsive audit of the ONLYOFFICE chrome (test only; run with
// agent-browser eval in a browser started with --disable-web-security so the
// harness page can read the DocServer iframe). Set window.__auditTab to a
// data-tab value first; the caller clicks the tab and waits.
// Prints one JSON object: issues[] is empty when the tab is clean.
(() => {
  const f = document.querySelector('iframe[name="frameEditor"], iframe');
  const d = f && f.contentDocument;
  if (!d) return JSON.stringify({ error: 'no iframe document' });
  const vis = (e) => {
    if (!e) return false;
    const r = e.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    for (let n = e; n && n !== d.body; n = n.parentElement) {
      const cs = getComputedStyle(n);
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
    }
    return true;
  };
  const R = (e) => {
    const r = e.getBoundingClientRect();
    return { x: Math.round(r.x), y: Math.round(r.y), r: Math.round(r.right), b: Math.round(r.bottom), w: Math.round(r.width), h: Math.round(r.height) };
  };
  const name = (e) => e.id || (e.querySelector('[id]') || {}).id || e.className.toString().slice(0, 40);
  const issues = [];
  const vw = d.documentElement.clientWidth;

  // ---- menu row (tabs + header buttons + logo)
  const tabsBox = d.querySelector('#toolbar .tabs');
  // Tabs scrolled out of the row (ONLYOFFICE's own scroll arrows on narrow
  // screens) are clipped by the <ul>: count only the part that shows.
  const clip = tabsBox && tabsBox.querySelector('ul') ? R(tabsBox.querySelector('ul')) : null;
  const tabs = [...d.querySelectorAll('#toolbar .tabs li.ribtab')].filter(vis);
  const tabRects = tabs
    .map((t) => {
      const r = { t: t.innerText.trim(), ...R(t) };
      if (clip) { r.x = Math.max(r.x, clip.x); r.r = Math.min(r.r, clip.r); }
      return r;
    })
    .filter((r) => r.r - r.x > 4);
  const shortTabs = tabsBox && tabsBox.classList.contains('short');
  const headerItems = [...d.querySelectorAll('#box-right-btn-group .btn-slot, #box-right-btn-group .box-cousers, #header-logo')].filter(vis);
  const headerRects = headerItems.map((e) => ({ id: name(e), ...R(e), txt: e.innerText.trim().slice(0, 20) }));
  const tabsRight = tabsBox ? R(tabsBox).r : 0;
  for (const h of headerRects) {
    if (h.r > vw + 1) issues.push(`header ${h.id} clipped at right (${h.r} > ${vw})`);
    // A tab under a header button = overlap.
    for (const t of tabRects) if (t.r > h.x + 1 && t.x < h.r - 1 && t.b > h.y && t.y < h.b) issues.push(`tab ${t.t} overlaps ${h.id}`);
  }
  // Tabs the build hides on purpose must not show.
  for (const t of tabRects) if (/^(Collaboration|Protection)$/.test(t.t)) issues.push(`tab ${t.t} still shown`);
  for (const id of ['slot-btn-edit-mode', 'tlb-box-users', 'slot-btn-close', 'left-btn-about']) if (vis(d.getElementById(id))) issues.push(`${id} still shown`);
  if (!vis(d.getElementById('header-logo'))) issues.push('logo not visible');
  for (const t of tabRects) {
    const a = tabs.find((x) => x.innerText.trim() === t.t).querySelector('a');
    if (a && a.scrollWidth > a.clientWidth + 1) issues.push(`tab ${t.t} text clipped`);
    if (a && a.getBoundingClientRect().height > 26) issues.push(`tab ${t.t} wraps (h=${Math.round(a.getBoundingClientRect().height)})`);
  }

  // ---- toolbar pill
  const pill = d.querySelector('#toolbar .box-controls');
  const panel = d.querySelector('#toolbar .box-controls .panel.active');
  const P = pill ? R(pill) : null;
  const A = panel ? R(panel) : null;
  const more = panel && panel.querySelector('.more-box');
  const moreVisible = more && vis(more);
  const M = moreVisible ? R(more) : null;
  if (P && A && A.h > P.h) issues.push(`panel taller than pill (${A.h} > ${P.h})`);
  const controls = panel ? [...panel.querySelectorAll('.btn-slot, .elset > *, .group > .btn-group, .combobox, .checkbox-indeterminate, .combo-dataview, label')].filter(vis).filter((e) => !(more && more.contains(e))) : [];
  const leaf = controls.filter((e) => !controls.some((o) => o !== e && e.contains(o)));
  for (const e of leaf) {
    const r = R(e);
    if (r.y < P.y - 1 || r.b > P.b + 1) issues.push(`${name(e)} outside pill vertically (${r.y}-${r.b} vs ${P.y}-${P.b})`);
    if (r.r > P.r + 1) issues.push(`${name(e)} past pill right (${r.r} > ${P.r})`);
    if (M && r.r > M.x + 1 && r.x < M.r) issues.push(`${name(e)} under the more button`);
    for (const c of e.querySelectorAll('.caption, label, .btn')) {
      if (!vis(c)) continue;
      if (c.scrollWidth > c.clientWidth + 1 && getComputedStyle(c).overflow !== 'visible') issues.push(`${name(e)} text clipped`);
    }
    const cap = e.querySelector('.caption');
    if (cap && vis(cap) && cap.getBoundingClientRect().height > 22) issues.push(`${name(e)} caption wraps`);
  }
  // Overlaps between distinct leaf controls.
  for (let i = 0; i < leaf.length; i++) {
    const a = R(leaf[i]);
    for (let j = i + 1; j < leaf.length; j++) {
      if (leaf[i].contains(leaf[j]) || leaf[j].contains(leaf[i])) continue;
      const b = R(leaf[j]);
      const ox = Math.min(a.r, b.r) - Math.max(a.x, b.x);
      const oy = Math.min(a.b, b.b) - Math.max(a.y, b.y);
      if (ox > 2 && oy > 2) issues.push(`${name(leaf[i])} overlaps ${name(leaf[j])}`);
    }
  }
  // Items that moved into ONLYOFFICE's overflow are reachable through "more".
  const moreBar = d.querySelector(`.more-container[data-tab="${panel && panel.dataset.tab}"]`);
  const inMore = moreBar ? moreBar.querySelectorAll('.btn-slot').length : 0;

  return JSON.stringify({
    vw,
    tab: panel && panel.dataset.tab,
    pill: P,
    panel: A,
    shortTabs,
    more: M ? { x: M.x, w: M.w } : null,
    inMore,
    controls: leaf.length,
    tabRow: { first: tabRects[0] || null, last: tabRects[tabRects.length - 1] || null, right: tabsRight },
    header: headerRects,
    issues: [...new Set(issues)],
  });
})()
