// about-check.js (test only / drylab.6): run with agent-browser
// eval on a harness page. Checks the Drylab About button in the editor's
// left strip: present, visible, at the bottom of the strip, same size as the
// strip's other buttons, not overlapping any of them, ONLYOFFICE's own About
// still hidden. Returns JSON {issues, btn, strip, others}.
(() => {
  const d = document.querySelector('iframe').contentDocument;
  const issues = [];
  const r = (e) => { const b = e.getBoundingClientRect(); return { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height), bottom: Math.round(b.bottom), right: Math.round(b.right) }; };
  const shown = (e) => { if (!e) return false; const b = e.getBoundingClientRect(); const cs = getComputedStyle(e); return b.width > 0 && b.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
  const btn = d.querySelector('#left-btn-drylab-about');
  const strip = d.querySelector('#left-menu .tool-menu-btns') || d.querySelector('.tool-menu.left .tool-menu-btns');
  if (!btn) return JSON.stringify({ issues: ['no #left-btn-drylab-about'] });
  if (!strip) return JSON.stringify({ issues: ['no left strip'] });
  if (!shown(btn)) issues.push('about button not visible');
  if (btn.classList.contains('disabled') || btn.disabled) issues.push('about button disabled');
  if (shown(d.querySelector('#left-btn-about'))) issues.push("ONLYOFFICE's own About entry shown");
  const B = r(btn), S = r(strip);
  if (S.bottom - B.bottom > 24 || B.bottom > S.bottom) issues.push(`not at the bottom: button bottom ${B.bottom}, strip bottom ${S.bottom}`);
  if (B.x < S.x || B.right > S.right) issues.push('outside the strip horizontally');
  const others = [...strip.querySelectorAll('button.btn-category')].filter((e) => e !== btn && shown(e));
  const ref = others.find((e) => e.id === 'left-btn-searchbar') || others[0];
  if (ref) {
    const R = r(ref);
    if (Math.abs(R.w - B.w) > 1 || Math.abs(R.h - B.h) > 1) issues.push(`size ${B.w}x${B.h} vs ${R.w}x${R.h}`);
  }
  for (const o of others) {
    const O = r(o);
    if (O.x < B.right && B.x < O.right && O.y < B.bottom && B.y < O.bottom) issues.push(`overlaps #${o.id || o.className}`);
  }
  const icon = btn.querySelector('.icon');
  const hint = btn.getAttribute('data-original-title') || btn.getAttribute('title') || btn.getAttribute('aria-label') || '';
  if (!/about/i.test(hint)) issues.push('hint is not About: ' + hint);
  return JSON.stringify({ issues, btn: B, strip: S, others: others.map((o) => o.id), icon: icon && icon.className, hint });
})()
