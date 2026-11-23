// DOM facts of the editor iframe (run with agent-browser eval in a browser
// started with --disable-web-security, test only, so the harness page can
// read the DocServer iframe). Prints one JSON object.
(() => {
  const f = document.querySelector('iframe[name="frameEditor"], iframe');
  const d = f && f.contentDocument;
  if (!d) return JSON.stringify({ error: 'no iframe document' });
  const q = (s) => d.querySelector(s);
  const box = (s) => {
    const e = q(s);
    if (!e) return 'absent';
    const r = e.getBoundingClientRect();
    const cs = getComputedStyle(e);
    if (cs.display === 'none' || cs.visibility === 'hidden' || r.height === 0 || r.width === 0) return 'hidden';
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), opacity: cs.opacity, bg: cs.backgroundColor, radius: cs.borderRadius };
  };
  // Is the logo covered by something else? Check the element at its centre.
  const logoCovered = (() => {
    const e = q('#header-logo');
    if (!e) return 'absent';
    const r = e.getBoundingClientRect();
    if (!r.width) return 'hidden';
    const hit = d.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return hit && (e === hit || e.contains(hit)) ? 'visible' : 'covered by ' + (hit ? hit.id || hit.className : 'null');
  })();
  const links = [...d.querySelectorAll('link[rel=stylesheet]')].map((l) => l.getAttribute('href')).filter((h) => /drylab/.test(h || ''));
  const tabs = [...d.querySelectorAll('#toolbar .ribtab:not(.x-lone)')].filter((t) => t.offsetParent).map((t) => {
    const a = t.querySelector('a') || t;
    const cs = getComputedStyle(a);
    return { text: t.innerText.trim(), bg: cs.backgroundColor, border: cs.borderBottom, radius: cs.borderRadius, active: t.classList.contains('active') };
  });
  const dialogs = [...d.querySelectorAll('.asc-window')].filter((e) => getComputedStyle(e).display !== 'none').map((e) => e.innerText.replace(/\s+/g, ' ').slice(0, 160));
  return JSON.stringify({
    drylabCss: links,
    drylabVar: getComputedStyle(d.body).getPropertyValue('--drylab-brand').trim() || null,
    bodyClass: d.body.className.slice(0, 120),
    header: box('#toolbar .box-tabs') ,
    toolbar: box('#toolbar .toolbar'),
    controls: box('#toolbar .box-controls'),
    logo: box('#header-logo'),
    logoCovered,
    leftMenu: box('#left-menu'),
    statusbar: box('#statusbar'),
    canvas: getComputedStyle(q('#editor_sdk') || d.body).backgroundColor,
    tabs,
    dialogs,
    events: window.__events,
  });
})()
