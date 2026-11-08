/* Mockup helpers: emblems (WoW tabard layers in an Albion-style metal shield), banner art, class icons.
   Class icons: the game's own icons, hot-linked from the Wowhead CDN only when rendering (no icon file is stored in the repo).
   Only for the HTML mockups: in the addon the same layers are WoW tabard textures referenced by fileID. */
(function () {
  let uid = 0;
  const SHIELD = 'M12 10 H88 V58 Q88 96 50 114 Q12 96 12 58 Z';
  const SHIELD_IN = 'M19 17 H81 V58 Q81 90 50 106 Q19 90 19 58 Z';

  function star(cx, cy, r1, r2, n) {
    let p = [];
    for (let i = 0; i < n * 2; i++) {
      const r = i % 2 ? r2 : r1, a = Math.PI * i / n - Math.PI / 2;
      p.push((cx + r * Math.cos(a)).toFixed(1) + ',' + (cy + r * Math.sin(a)).toFixed(1));
    }
    return `<polygon points="${p.join(' ')}"/>`;
  }
  const SYMBOLS = {
    star: () => star(50, 58, 27, 9, 4) + star(50, 58, 17, 7, 4).replace('<polygon', '<polygon transform="rotate(45 50 58)"'),
    star8: () => star(50, 58, 26, 10, 8),
    sun: () => `<circle cx="50" cy="58" r="11"/>` + star(50, 58, 27, 14, 12),
    cross: () => `<path d="M45 28h10v19h17v10H55v29H45V57H28V47h17z"/>`,
    crescent: () => `<path d="M60 34a24 24 0 1 0 0 48a30 30 0 0 1 0-48z"/>` + star(66, 52, 7, 3, 4),
    sword: () => `<path d="M50 24l5 9v38h-10V33z"/><rect x="35" y="70" width="30" height="6" rx="2"/><rect x="47.5" y="76" width="5" height="10"/><circle cx="50" cy="89" r="4"/>`,
    crown: () => `<path d="M29 74V46l11 13 10-21 10 21 11-13v28z"/><rect x="29" y="77" width="42" height="6" rx="1.5"/>`,
    tower: () => `<path d="M34 86V48h4v-6h5v6h4v-6h6v6h4v-6h5v6h4v38z"/><path d="M46 86v-12a4 4 0 0 1 8 0v12z" fill="rgba(0,0,0,.45)"/>`,
    flame: () => `<path d="M50 26c10 14 20 22 16 38-2 12-10 20-16 20-8 0-16-8-16-20 0-10 8-14 10-24 4 8 6 12 10 10 2-6 0-16-4-24z"/>`,
    hood: () => `<path d="M50 26c-16 0-26 16-24 34 1 12 6 20 12 26h24c6-6 11-14 12-26 2-18-8-34-24-34z"/><path d="M50 46c-8 0-12 8-12 16 0 8 5 14 12 16 7-2 12-8 12-16 0-8-4-16-12-16z" fill="rgba(0,0,0,.55)"/>`,
    beast: () => `<path d="M30 40l8 4 4-10 8 8 8-8 4 10 8-4-2 14c4 4 4 10 0 14l-6 6-6 10H44l-6-10-6-6c-4-4-4-10 0-14z"/><circle cx="43" cy="60" r="2.6" fill="rgba(0,0,0,.6)"/><circle cx="57" cy="60" r="2.6" fill="rgba(0,0,0,.6)"/>`,
    leaf: () => `<path d="M50 24c14 12 20 26 18 40-2 12-10 20-18 22-8-2-16-10-18-22-2-14 4-28 18-40z"/><path d="M50 30v56" stroke="rgba(0,0,0,.4)" stroke-width="2"/>`
  };

  /* emblem({bg, bc, ec, border, symbol, size}) -> svg string */
  function emblem(o) {
    const id = 'e' + (++uid);
    const bg = o.bg || '#1b2a44', bc = o.bc || '#c9c9c9', ec = o.ec || '#ffffff';
    const sym = (SYMBOLS[o.symbol] || SYMBOLS.star)();
    if (o.bare) return `<svg viewBox="14 20 72 76" xmlns="http://www.w3.org/2000/svg" width="100%" height="100%"><g fill="${ec}">${sym}</g></svg>`;
    let border = '';
    switch (o.border || 'solid') {
      case 'double': border = `<path d="${SHIELD_IN}" fill="none" stroke="${bc}" stroke-width="3"/><path d="${SHIELD_IN}" transform="translate(50 60) scale(.88) translate(-50 -60)" fill="none" stroke="${bc}" stroke-width="2"/>`; break;
      case 'studded': border = `<path d="${SHIELD_IN}" fill="none" stroke="${bc}" stroke-width="5" stroke-dasharray="1 6" stroke-linecap="round"/>`; break;
      case 'bold': border = `<path d="${SHIELD_IN}" fill="none" stroke="${bc}" stroke-width="7"/>`; break;
      case 'none': border = ''; break;
      default: border = `<path d="${SHIELD_IN}" fill="none" stroke="${bc}" stroke-width="4"/>`;
    }
    let field = `<path d="${SHIELD}" fill="${bg}"/>`;
    if (o.split) field += `<path d="M50 10H88V58Q88 96 50 114Z" fill="${o.split}"/>`;
    if (o.chief) field += `<path d="M12 10H88V40H12Z" fill="${o.chief}"/>`;
    return `<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg" width="100%" height="100%">
      <defs>
        <linearGradient id="${id}m" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f4f7fa"/><stop offset=".35" stop-color="#a3adb7"/><stop offset=".55" stop-color="#e3e8ed"/><stop offset="1" stop-color="#5a636c"/></linearGradient>
        <radialGradient id="${id}h" cx=".35" cy=".25" r=".9"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".35"/></radialGradient>
        <clipPath id="${id}c"><path d="${SHIELD}"/></clipPath>
        <filter id="${id}s" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="1.2" stdDeviation="1" flood-opacity=".55"/></filter>
      </defs>
      <g clip-path="url(#${id}c)">${field}<rect width="100" height="120" fill="url(#${id}h)"/></g>
      ${border}
      <g fill="${ec}" filter="url(#${id}s)">${sym}</g>
      <path d="${SHIELD}" fill="none" stroke="#1d2126" stroke-width="9"/>
      <path d="${SHIELD}" fill="none" stroke="url(#${id}m)" stroke-width="6"/>
      <path d="${SHIELD}" fill="none" stroke="rgba(0,0,0,.35)" stroke-width="1" transform="translate(50 60) scale(.955) translate(-50 -60)"/>
    </svg>`;
  }

  /* banner art: generated fantasy vista (stand-in for client loading-screen art) */
  const THEMES = {
    emerald: { sky: ['#071a17', '#1d5546', '#4f9f7f'], glow: '#9bffd6', m: ['#2c6656', '#1b4639', '#0f2a22'], s: '#08150f', p: '#b6ffe1', kind: 'spires' },
    ember:   { sky: ['#1f0904', '#7a2a0e', '#e07a2c'], glow: '#ffd27a', m: ['#7a3416', '#4d1e0c', '#290e05'], s: '#160603', p: '#ffcf70', kind: 'castle' },
    frost:   { sky: ['#0b1626', '#3d6390', '#a9cbea'], glow: '#f2fbff', m: ['#6a8db3', '#3e5f85', '#1d3350'], s: '#0d1a2b', p: '#ffffff', kind: 'castle' },
    dusk:    { sky: ['#140a24', '#5a2e66', '#d07a8a'], glow: '#ffc2d6', m: ['#5a3a6e', '#38234a', '#1d1028'], s: '#0f0717', p: '#ffd6e6', kind: 'tree' },
    gold:    { sky: ['#2a1806', '#9a6420', '#f0c46a'], glow: '#fff3c4', m: ['#b07a34', '#7a5020', '#43290c'], s: '#24160a', p: '#fff0b8', kind: 'ruins' },
    storm:   { sky: ['#0b0d10', '#2f3a46', '#7f93a6'], glow: '#cfe3ff', m: ['#4a5866', '#2d3640', '#161b21'], s: '#0a0c0f', p: '#d8e8ff', kind: 'spires' }
  };
  function rng(seed) { let s = seed || 7; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
  function ridge(r, y0, amp, step, w) {
    let pts = [`0,160`, `0,${y0}`]; let x = 0;
    while (x < w) { x += step * (0.6 + r()); pts.push(`${x.toFixed(0)},${(y0 - amp * r()).toFixed(0)}`); }
    pts.push(`${w},160`); return pts.join(' ');
  }
  function structure(kind, c, r) {
    if (kind === 'castle') return `<g fill="${c}"><rect x="380" y="70" width="120" height="70"/><rect x="370" y="50" width="22" height="90"/><rect x="488" y="44" width="24" height="96"/><rect x="430" y="30" width="26" height="110"/>
      <path d="M368 50l13-16 13 16zM486 44l14-18 14 18zM428 30l15-22 15 22z"/><rect x="520" y="86" width="60" height="54"/><rect x="560" y="60" width="18" height="80"/><path d="M558 60l11-14 11 14z"/></g>
      <g fill="#ffcf70" opacity=".8"><rect x="438" y="56" width="4" height="7"/><rect x="496" y="70" width="4" height="7"/><rect x="378" y="80" width="4" height="6"/></g>`;
    if (kind === 'spires') return `<g fill="${c}"><path d="M420 140L432 20l12 120z"/><path d="M455 140l9-90 9 90z"/><path d="M392 140l7-60 7 60z"/><path d="M490 140l10-70 10 70z"/><path d="M520 140l6-40 6 40z"/><rect x="380" y="118" width="170" height="22"/></g>`;
    if (kind === 'tree') return `<g fill="${c}"><path d="M470 140c-4-30 2-50 0-70-16-2-40-10-48-26 18 6 34 6 46 0-10-12-12-26-6-38 8 14 16 22 24 26 6-14 18-22 34-24-8 10-12 22-12 34 16-4 30 0 40 10-16 0-28 4-36 12 4 20 2 48-6 76z"/></g>`;
    return `<g fill="${c}"><rect x="400" y="60" width="16" height="80"/><rect x="480" y="50" width="16" height="90"/><path d="M400 60h96v14h-96z"/><rect x="530" y="90" width="14" height="50"/><path d="M380 140l10-20h30l6 20z"/></g>`;
  }
  function art(theme, seed) {
    const t = THEMES[theme] || THEMES.emerald, r = rng(seed), id = 'a' + (++uid);
    let parts = '';
    for (let i = 0; i < 26; i++) parts += `<circle cx="${(330 + r() * 270).toFixed(0)}" cy="${(10 + r() * 130).toFixed(0)}" r="${(0.6 + r() * 1.6).toFixed(1)}" fill="${t.p}" opacity="${(0.3 + r() * 0.6).toFixed(2)}"/>`;
    return `<svg viewBox="0 0 600 160" preserveAspectRatio="xMaxYMid slice" xmlns="http://www.w3.org/2000/svg">
      <defs><linearGradient id="${id}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${t.sky[0]}"/><stop offset=".6" stop-color="${t.sky[1]}"/><stop offset="1" stop-color="${t.sky[2]}"/></linearGradient>
      <radialGradient id="${id}g" cx=".72" cy=".55" r=".45"><stop offset="0" stop-color="${t.glow}" stop-opacity=".85"/><stop offset=".4" stop-color="${t.glow}" stop-opacity=".25"/><stop offset="1" stop-color="${t.glow}" stop-opacity="0"/></radialGradient>
      <linearGradient id="${id}f" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" stop-color="${t.sky[2]}" stop-opacity="0"/><stop offset="1" stop-color="${t.sky[2]}" stop-opacity=".45"/></linearGradient></defs>
      <rect width="600" height="160" fill="url(#${id}s)"/><rect width="600" height="160" fill="url(#${id}g)"/>
      <polygon points="${ridge(r, 92, 46, 34, 600)}" fill="${t.m[0]}" opacity=".85"/>
      ${structure(t.kind, t.s, r)}
      <polygon points="${ridge(r, 122, 26, 46, 600)}" fill="${t.m[1]}"/>
      <rect width="600" height="160" fill="url(#${id}f)"/>
      <polygon points="${ridge(r, 148, 16, 60, 600)}" fill="${t.m[2]}"/>
      ${parts}</svg>`;
  }

  const CLASSES = { warrior: ['Wa', '--c-warrior'], paladin: ['Pa', '--c-paladin'], hunter: ['Hu', '--c-hunter'], rogue: ['Ro', '--c-rogue'], priest: ['Pr', '--c-priest'], shaman: ['Sh', '--c-shaman'], mage: ['Ma', '--c-mage'], warlock: ['Wl', '--c-warlock'], druid: ['Dr', '--c-druid'] };
  const ROLES = { t: 'shield', h: 'health_cross', m: 'swords', r: 'target', d: 'swords' };
  const ROLE_NAMES = { t: 'Tank', h: 'Healer', m: 'Melee DPS', r: 'Ranged DPS', d: 'DPS' };

  function render(root) {
    root.querySelectorAll('[data-emblem]').forEach(el => { el.innerHTML = emblem(JSON.parse(el.dataset.emblem)); });
    root.querySelectorAll('[data-art]').forEach(el => { const [t, s] = el.dataset.art.split(':'); el.innerHTML = art(t, +s || 7); });
    root.querySelectorAll('[data-cls]').forEach(el => { const c = CLASSES[el.dataset.cls]; if (!c) return; el.classList.add('cls'); el.style.setProperty('--c', `var(${c[1]})`); el.textContent = ''; el.title = el.dataset.cls;
      el.style.backgroundImage = `url(https://wow.zamimg.com/images/wow/icons/large/classicon_${el.dataset.cls}.jpg)`; });
    root.querySelectorAll('[data-role]').forEach(el => { el.classList.add('role', el.dataset.role); el.title = ROLE_NAMES[el.dataset.role]; el.innerHTML = `<span class="ms">${ROLES[el.dataset.role]}</span>`; });
  }
  window.AGF = { emblem, art, render };
  document.addEventListener('DOMContentLoaded', () => {
    if (/[?&]clean/.test(location.search)) document.body.classList.add('clean');
    render(document);
  });
})();
