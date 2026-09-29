// NERV HQ terminal kit — plain-JS port of app/src/scenes/_eva.ts (+ magi-hud / atfield-kit helpers)
// for still wallpapers. Everything is drawn in logical 1920x1200 units, output 2560x1600.
'use strict';
const OUT_W = 2560, OUT_H = 1600, W = 1920, H = 1200, S = OUT_W / W;
const TAU = Math.PI * 2;
const HEX = {
  ink: '#050403', ink2: '#120C06', graphite: '#4A3218', ash: '#9C6A2E', bone: '#FFE9C8', metal: '#C8B8A0',
  orange: '#FF7A00', amber: '#FFB000', red: '#FF1A1A', blood: '#6A0000', green: '#39FF6A', cyan: '#00C8FF',
  purple: '#7A3CFF', lime: '#B6FF00',
};
function rgba(key, a = 1) {
  const hex = HEX[key] ?? key;
  const n = parseInt(hex.replace('#', ''), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;
function hash(...xs) {
  let h = 2166136261 >>> 0;
  for (const x of xs) {
    h ^= Math.floor(x * 1000003) | 0;
    h = Math.imul(h, 16777619); h ^= h >>> 13;
    h = Math.imul(h, 0x5bd1e995); h ^= h >>> 15;
  }
  return (h >>> 0) / 4294967296;
}
function noise1(x, seed = 0) {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i, seed) * 2 - 1, hash(i + 1, seed) * 2 - 1, u);
}
function fbm(x, seed = 0, oct = 4) { let s = 0, a = 0.5, fr = 1; for (let i = 0; i < oct; i++) { s += a * noise1(x * fr, seed + i * 17); a *= 0.5; fr *= 2.03; } return s; }

// ---------------------------------------------------------------- synthetic "frozen frame" audio
// A deterministic song-like signal: kick every beat, bass line, pads, hats.
const BPM = 133.33, BEAT = 60 / BPM;
function synthWave(t, seed = 1) {
  const bt = ((t % BEAT) + BEAT) % BEAT;
  const kick = Math.exp(-bt / 0.09) * Math.sin(TAU * (48 + 90 * Math.exp(-bt / 0.02)) * bt);
  const bass = 0.35 * Math.sin(TAU * 55 * t + 0.6 * Math.sin(TAU * 110 * t)) * (0.5 + 0.5 * Math.sin(TAU * t / BEAT / 2));
  const pad = 0.16 * (Math.sin(TAU * 220 * t) + 0.6 * Math.sin(TAU * 277.2 * t + 1) + 0.4 * Math.sin(TAU * 329.6 * t + 2));
  const hat = 0.12 * (hash(Math.floor(t * 44100), seed) * 2 - 1) * Math.exp(-(((t + BEAT / 2) % BEAT)) / 0.03);
  return clamp(0.8 * kick + bass + pad + hat, -1, 1);
}
/** mel-ish spectrum of 64 bands at a frozen moment: pink falloff + bumps + jitter. */
function synthSpectrum(n = 64, seed = 3) {
  const a = [];
  for (let b = 0; b < n; b++) {
    const k = b / n;
    let v = 0.92 - 0.55 * k + 0.18 * Math.exp(-((k - 0.08) ** 2) / 0.002) + 0.12 * Math.exp(-((k - 0.42) ** 2) / 0.006) + 0.1 * Math.exp(-((k - 0.72) ** 2) / 0.004);
    v += 0.16 * (hash(b, seed) - 0.5) + 0.08 * noise1(b * 0.4, seed);
    a.push(clamp(v));
  }
  return a;
}

// ---------------------------------------------------------------- fonts
const FONT_DIR = new URL('../../fonts/', location.href).href;
const FONTS = [
  ['Corm', 'Cormorant-600.ttf', '"lnum" 1'], ['Corm4', 'Cormorant-400.ttf', '"lnum" 1'],
  ['Plex-300', 'IBMPlexMono-Light.ttf'], ['Plex-400', 'IBMPlexMono-Regular.ttf'], ['Plex-500', 'IBMPlexMono-Medium.ttf'],
  ['Plex-600', 'IBMPlexMono-SemiBold.ttf'], ['Plex-700', 'IBMPlexMono-Bold.ttf'],
];
async function loadFonts() {
  await Promise.all(FONTS.map(async ([fam, file, feat]) => {
    const ff = new FontFace(fam, `url(${FONT_DIR}${file})`, feat ? { featureSettings: feat } : undefined);
    await ff.load(); document.fonts.add(ff);
  }));
  // CJK system fonts: force-load the weights we use
  const probes = ['400 20px "Noto Sans CJK JP"', '700 20px "Noto Sans CJK JP"', '900 20px "Noto Sans CJK JP"', '600 20px "Noto Serif CJK JP"', '700 20px "Noto Serif CJK JP"', '900 20px "Noto Serif CJK JP"'];
  await Promise.all(probes.map((p) => document.fonts.load(p, '承認否決第3新東京市')));
  await document.fonts.ready;
}
const mono = (w, px) => `${px}px "Plex-${[300, 400, 500, 600, 700].reduce((b, x) => (Math.abs(x - w) < Math.abs(b - w) ? x : b), 400)}"`;
const JP_SERIF = '"Noto Serif CJK JP", serif', JP_SANS = '"Noto Sans CJK JP", sans-serif';
const jp = (px, weight = 600, serif = true) => `${weight} ${px}px ${serif ? JP_SERIF : JP_SANS}`;

// ---------------------------------------------------------------- canvas
function makeCanvas() {
  const cv = document.getElementById('c');
  cv.width = OUT_W; cv.height = OUT_H;
  const c = cv.getContext('2d', { willReadFrequently: false });
  c.setTransform(S, 0, 0, S, 0, 0);
  c.fillStyle = HEX.ink; c.fillRect(0, 0, W, H);
  return { cv, c };
}

// ---------------------------------------------------------------- type
function condensed(c, text, x, y, size, o = {}) {
  const sx = o.sx ?? 0.62;
  c.save();
  c.font = `${size}px "${o.family ?? 'Corm'}"`;
  c.letterSpacing = `${o.tracking ?? 0}px`;
  c.textBaseline = 'alphabetic';
  const w = c.measureText(text).width * sx;
  const al = o.align ?? 'left';
  const x0 = al === 'center' ? x - w / 2 : al === 'right' ? x - w : x;
  c.translate(x0, y); c.scale(sx, 1);
  c.textAlign = 'left';
  c.fillStyle = o.color ?? rgba('bone', 1);
  if (o.glow) { c.shadowColor = o.glowColor ?? c.fillStyle; c.shadowBlur = o.glow; }
  c.fillText(text, 0, 0);
  const bd = o.bold ?? 0.022;
  if (bd > 0) { c.strokeStyle = c.fillStyle; c.lineWidth = size * bd; c.lineJoin = 'miter'; c.strokeText(text, 0, 0); }
  c.restore();
  return w;
}
/** natural (unsqueezed) width of a condensed line */
function condW(c, text, size, family = 'Corm') { c.save(); c.font = `${size}px "${family}"`; c.letterSpacing = '0px'; const w = c.measureText(text).width; c.restore(); return w; }

function evaTitle(c, x, y, lines, o = {}) {
  let yy = y;
  lines.forEach(([txt, size, sx]) => { yy += size * (o.lead ?? 0.86); condensed(c, txt, x, yy, size, { sx: sx ?? 0.6, color: o.color, align: o.align }); });
  return yy;
}
function evaLabel(c, x, y, en, jpText, o = {}) {
  const s = o.size ?? 1, a = o.alpha ?? 1;
  c.save(); c.globalAlpha *= a;
  c.textAlign = o.align ?? 'left'; c.textBaseline = 'alphabetic';
  c.fillStyle = o.color ?? rgba('orange', 1);
  c.font = mono(600, 13 * s); c.letterSpacing = `${2.4 * s}px`;
  c.fillText(en.toUpperCase(), x, y);
  c.letterSpacing = '0px';
  if (jpText) { c.font = jp(15 * s, 600, false); c.fillText(jpText, x, y + 20 * s); }
  c.restore();
}
function txt(c, s, x, y, size, color, o = {}) {
  c.save();
  c.font = mono(o.w ?? 500, size); c.letterSpacing = `${o.track ?? size * 0.16}px`;
  c.fillStyle = color; c.textAlign = o.align ?? 'left'; c.textBaseline = o.base ?? 'alphabetic';
  c.fillText(s, x, y);
  const w = c.measureText(s).width;
  c.restore();
  return w;
}
function jpText(c, s, x, y, size, color, o = {}) {
  c.save(); c.font = jp(size, o.w ?? 700, o.serif ?? false); c.fillStyle = color; c.textAlign = o.align ?? 'left'; c.textBaseline = o.base ?? 'alphabetic';
  c.fillText(s, x, y); const w = c.measureText(s).width; c.restore(); return w;
}
function jpVertical(c, text, x, y, size, color, serif = true, lead = 1.08) {
  c.save(); c.font = jp(size, 700, serif); c.fillStyle = color; c.textAlign = 'center'; c.textBaseline = 'top';
  let yy = y; for (const ch of text) { c.fillText(ch, x, yy); yy += size * lead; }
  c.restore(); return yy;
}

// ---------------------------------------------------------------- shapes
function chamferPath(c, x, y, w, h, cut = 14) {
  const [a, b, d, e] = typeof cut === 'number' ? [cut, cut, cut, cut] : cut;
  c.beginPath();
  c.moveTo(x + a, y); c.lineTo(x + w - b, y); c.lineTo(x + w, y + b);
  c.lineTo(x + w, y + h - d); c.lineTo(x + w - d, y + h); c.lineTo(x + e, y + h);
  c.lineTo(x, y + h - e); c.lineTo(x, y + a); c.closePath();
}
function panel(c, x, y, w, h, o = {}) {
  const col = o.color ?? rgba('orange', 1), a = o.alpha ?? 1, cut = o.cut ?? 16, hh = o.title ? (o.header ?? 30) : 0;
  c.save(); c.globalAlpha *= a;
  chamferPath(c, x, y, w, h, [0, cut, 0, cut]);
  c.fillStyle = o.fill ?? 'rgba(18,12,6,0.78)'; c.fill();
  c.strokeStyle = col; c.lineWidth = o.lw ?? 1.5; c.stroke();
  if (o.title) {
    c.font = mono(700, 14); c.letterSpacing = '2px';
    const tw = c.measureText(o.title.toUpperCase()).width;
    c.letterSpacing = '0px'; c.font = jp(15, 700, false);
    const jw = o.jp ? c.measureText(o.jp).width + 14 : 0;
    c.fillStyle = col;
    chamferPath(c, x, y, Math.min(w * 0.8, tw + jw + 40), hh, [0, hh * 0.6, 0, 0]); c.fill();
    c.fillStyle = rgba('ink', 1);
    c.font = mono(700, 14); c.letterSpacing = '2px'; c.textBaseline = 'middle';
    c.fillText(o.title.toUpperCase(), x + 12, y + hh / 2 + 1);
    c.letterSpacing = '0px';
    if (o.jp) { c.font = jp(15, 700, false); c.fillText(o.jp, x + 24 + tw, y + hh / 2 + 1); }
    if (o.right) { c.font = mono(600, 11); c.letterSpacing = '2px'; c.textAlign = 'right'; c.fillStyle = col; c.globalAlpha *= 0.8; c.fillText(o.right, x + w - 22, y + hh / 2 + 1); c.globalAlpha /= 0.8; c.textAlign = 'left'; c.letterSpacing = '0px'; }
    c.strokeStyle = col; c.globalAlpha *= 0.5; c.lineWidth = 1;
    c.beginPath(); c.moveTo(x + 6, y + hh + 4); c.lineTo(x + w - 6, y + hh + 4); c.stroke();
  }
  c.restore();
  return { x: x + 10, y: y + hh + 12, w: w - 20, h: h - hh - 22 };
}
function brackets(c, x, y, w, h, len = 18, color = rgba('orange', 1), lw = 2) {
  c.save(); c.strokeStyle = color; c.lineWidth = lw; c.lineCap = 'square';
  c.beginPath();
  c.moveTo(x, y + len); c.lineTo(x, y); c.lineTo(x + len, y);
  c.moveTo(x + w - len, y); c.lineTo(x + w, y); c.lineTo(x + w, y + len);
  c.moveTo(x + w, y + h - len); c.lineTo(x + w, y + h); c.lineTo(x + w - len, y + h);
  c.moveTo(x + len, y + h); c.lineTo(x, y + h); c.lineTo(x, y + h - len);
  c.stroke(); c.restore();
}
function hexPath(c, cx, cy, r, rot = 0, begin = true) {
  if (begin) c.beginPath();
  for (let i = 0; i < 6; i++) {
    const a = rot + Math.PI / 6 + (i * TAU) / 6;
    const px = cx + r * Math.cos(a), py = cy + r * Math.sin(a);
    if (i === 0) c.moveTo(px, py); else c.lineTo(px, py);
  }
  c.closePath();
}
function hexGrid(x, y, w, h, r, fn) {
  const dx = Math.sqrt(3) * r, dy = 1.5 * r;
  let i = 0;
  for (let row = 0; y + row * dy <= y + h + r; row++)
    for (let col = 0; x + col * dx <= x + w + dx; col++) fn(x + col * dx + (row % 2 ? dx / 2 : 0), y + row * dy, col, row, i++);
}
function octPath(c, cx, cy, r) {
  const k = r * Math.tan(Math.PI / 8);
  c.beginPath();
  c.moveTo(cx - k, cy - r); c.lineTo(cx + k, cy - r); c.lineTo(cx + r, cy - k); c.lineTo(cx + r, cy + k);
  c.lineTo(cx + k, cy + r); c.lineTo(cx - k, cy + r); c.lineTo(cx - r, cy + k); c.lineTo(cx - r, cy - k); c.closePath();
}
function hazard(c, x, y, w, h, phase = 0, a = rgba('red', 1), b = null, stripe = 26) {
  c.save(); c.beginPath(); c.rect(x, y, w, h); c.clip();
  if (b) { c.fillStyle = b; c.fillRect(x, y, w, h); }
  c.fillStyle = a;
  const p = ((phase % (stripe * 2)) + stripe * 2) % (stripe * 2);
  for (let sx = x - h - stripe * 2 + p; sx < x + w + stripe; sx += stripe * 2) {
    c.beginPath(); c.moveTo(sx, y + h); c.lineTo(sx + h, y); c.lineTo(sx + h + stripe, y); c.lineTo(sx + stripe, y + h); c.closePath(); c.fill();
  }
  c.restore();
}

// ---------------------------------------------------------------- instruments
const SEG = { '0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': '', A: 'abcefg', E: 'adefg', F: 'aefg', H: 'bcefg', L: 'def', P: 'abefg', r: 'eg', o: 'cdeg', U: 'bcdef', n: 'ceg', t: 'defg', d: 'bcdeg', b: 'cdefg', C: 'adef', S: 'acdfg' };
function sevenSeg(c, text, x, y, h, color = rgba('orange', 1), dim = rgba('orange', 0.08), o = {}) {
  const w = h * 0.52, t = o.thick ?? h * 0.11, sk = o.skew ?? 0.1, gap = t * 0.18;
  let cx = x;
  c.save();
  if (o.glow) { c.shadowColor = color; c.shadowBlur = o.glow; }
  const seg = (on, pts) => {
    if (!on && !dim) return;
    c.fillStyle = on ? color : dim;
    c.beginPath();
    pts.forEach(([px, py], i) => { const X = cx + px + (h - py) * sk, Y = y + py; if (i) c.lineTo(X, Y); else c.moveTo(X, Y); });
    c.closePath(); c.fill();
  };
  for (const ch of text) {
    if (ch === ':' || ch === '.') {
      c.fillStyle = color;
      if (ch === ':') { c.fillRect(cx + t * 0.6 + h * 0.66 * sk, y + h * 0.3, t, t); c.fillRect(cx + t * 0.6 + h * 0.3 * sk, y + h * 0.66, t, t); }
      else c.fillRect(cx + t * 0.4, y + h - t, t, t);
      cx += t * 2.6; continue;
    }
    const on = SEG[ch] ?? '';
    const m = h / 2, hw = t / 2;
    const hz = (yy) => [[gap + hw, yy], [gap + t, yy - hw], [w - gap - t, yy - hw], [w - gap - hw, yy], [w - gap - t, yy + hw], [gap + t, yy + hw]];
    const vt = (xx, y0, y1) => [[xx, y0 + gap + hw], [xx + hw, y0 + gap + t], [xx + hw, y1 - gap - t], [xx, y1 - gap - hw], [xx - hw, y1 - gap - t], [xx - hw, y0 + gap + t]];
    seg(on.includes('a'), hz(hw)); seg(on.includes('g'), hz(m)); seg(on.includes('d'), hz(h - hw));
    seg(on.includes('f'), vt(hw, 0, m)); seg(on.includes('b'), vt(w - hw, 0, m));
    seg(on.includes('e'), vt(hw, m, h)); seg(on.includes('c'), vt(w - hw, m, h));
    cx += w + t * 1.2;
  }
  c.restore();
  return cx - x;
}
function segWidth(text, h, thick = h * 0.11) { let w = 0; for (const ch of text) w += ch === ':' || ch === '.' ? thick * 2.6 : h * 0.52 + thick * 1.2; return w; }
function segMeter(c, x, y, w, h, n, v, o = {}) {
  const g = o.gap ?? 2, lit = v * n;
  c.save();
  for (let i = 0; i < n; i++) {
    const k = i / n;
    const col = k >= (o.hotFrom ?? 0.8) ? (o.hot ?? rgba('red', 1)) : (o.color ?? rgba('orange', 1));
    const on = i < Math.floor(lit) ? 1 : i < lit ? lit - i : 0;
    c.fillStyle = on > 0 ? col : (o.dim ?? rgba('orange', 0.1));
    c.globalAlpha = on > 0 ? 0.35 + 0.65 * on : 1;
    if (o.vertical) { const bh = (h - g * (n - 1)) / n; c.fillRect(x, y + h - (i + 1) * bh - i * g, w, bh); }
    else { const bw = (w - g * (n - 1)) / n; c.fillRect(x + i * (bw + g), y, bw, h); }
  }
  c.restore();
}
function scale(c, x0, y0, x1, y1, n, o = {}) {
  const dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy), nx = (dy / L) * (o.side ?? 1), ny = (-dx / L) * (o.side ?? 1), tk = o.tick ?? 6, mj = o.major ?? 5;
  c.save();
  c.strokeStyle = o.color ?? rgba('orange', 0.8); c.fillStyle = o.color ?? rgba('orange', 0.8); c.lineWidth = 1;
  c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, y1);
  for (let i = 0; i <= n; i++) { const px = x0 + (dx * i) / n, py = y0 + (dy * i) / n, len = i % mj === 0 ? tk * 1.8 : tk; c.moveTo(px, py); c.lineTo(px + nx * len, py + ny * len); }
  c.stroke();
  if (o.label) {
    c.font = mono(500, 11); c.textAlign = 'center'; c.textBaseline = 'middle';
    for (let i = 0; i <= n; i += mj) { const s = o.label(i); if (s) c.fillText(s, x0 + (dx * i) / n + nx * (tk * 1.8 + 12), y0 + (dy * i) / n + ny * (tk * 1.8 + 12)); }
  }
  c.restore();
}
function warningBox(c, x, y, w, h, word, jpT, o = {}) {
  const col = o.color ?? rgba('red', 1), bl = o.blink ?? 1;
  c.save();
  chamferPath(c, x, y, w, h, 18);
  c.fillStyle = `rgba(40,0,0,${0.55 + 0.35 * bl})`; c.fill();
  c.strokeStyle = col; c.lineWidth = 3; c.stroke();
  const band = h * 0.14;
  hazard(c, x + 10, y + 10, w - 20, band, o.phase ?? 0, col);
  hazard(c, x + 10, y + h - 10 - band, w - 20, band, -(o.phase ?? 0), col);
  condensed(c, word, x + w / 2, y + h * 0.66, h * 0.46, { sx: 0.58, color: col, align: 'center' });
  c.font = jp(h * 0.11, 700, false); c.fillStyle = col; c.textAlign = 'center';
  c.fillText(jpT, x + w / 2, y + h * 0.8);
  c.restore();
}
/** frozen ticker: text repeated from a seeded offset, clipped to [x, x+w] */
function ticker(c, x, y, w, text, off = 0, o = {}) {
  c.save();
  const sz = o.size ?? 13;
  c.beginPath(); c.rect(x, y - sz - 4, w, sz + 10); c.clip();
  c.font = mono(500, sz); c.fillStyle = o.color ?? rgba('orange', 0.85); c.letterSpacing = '2px';
  const tw = c.measureText(text + '   ').width;
  for (let ox = -(off % tw); ox < w; ox += tw) c.fillText(text + '   ', x + ox, y);
  c.restore();
}
function hexData(seed, step, n = 8) { let s = ''; for (let i = 0; i < n; i++) s += Math.floor(hash(seed, step, i) * 16).toString(16).toUpperCase(); return s; }
function meta(c, x, y, rows, o = {}) {
  const s = o.size ?? 13, lead = o.lead ?? s * 1.65, kw = o.keyW ?? 118;
  c.save(); c.fillStyle = o.color ?? rgba('orange', 1);
  c.font = mono(600, s); c.letterSpacing = '1.5px'; c.textBaseline = 'alphabetic';
  rows.forEach(([k, v], i) => { c.fillText(k, x, y + i * lead); c.fillText(': ' + v, x + kw, y + i * lead); });
  c.restore();
}
function statusRow(c, x, y, w, en, jpT, value, vcol, o = {}) {
  const col = o.col ?? rgba('orange', 0.9);
  c.save(); c.textBaseline = 'alphabetic';
  c.font = mono(600, 13); c.letterSpacing = '2px'; c.fillStyle = col; c.fillText(en, x, y);
  const ew = c.measureText(en).width;
  c.letterSpacing = '0px'; c.font = jp(13, 600, false); c.fillStyle = rgba('orange', 0.6); c.fillText(jpT, x + ew + 10, y);
  const jw = c.measureText(jpT).width;
  c.font = mono(700, 13); c.letterSpacing = '1.5px';
  const vw = c.measureText(value).width;
  c.fillStyle = rgba('orange', 0.35);
  for (let d = x + ew + jw + 20; d < x + w - vw - 16; d += 6) c.fillRect(d, y - 2, 2, 2);
  if (o.box) { c.fillStyle = vcol; c.fillRect(x + w - vw - 10, y - 13, vw + 10, 17); c.fillStyle = rgba('ink', 1); } else c.fillStyle = vcol;
  c.textAlign = 'right'; c.fillText(value, x + w - (o.box ? 5 : 0), y);
  c.restore();
}
function graticule(c, x, y, w, h, col = 'orange', nx = 8, ny = 4) {
  c.save(); c.strokeStyle = rgba(col, 0.16); c.lineWidth = 1; c.beginPath();
  for (let i = 0; i <= nx; i++) { c.moveTo(x + (w * i) / nx, y); c.lineTo(x + (w * i) / nx, y + h); }
  for (let i = 0; i <= ny; i++) { c.moveTo(x, y + (h * i) / ny); c.lineTo(x + w, y + (h * i) / ny); }
  c.stroke();
  c.strokeStyle = rgba(col, 0.4); c.beginPath(); c.moveTo(x, y + h / 2); c.lineTo(x + w, y + h / 2); c.stroke();
  // centre ticks
  c.beginPath(); for (let i = 0; i <= nx * 5; i++) { const px = x + (w * i) / (nx * 5); c.moveTo(px, y + h / 2 - 3); c.lineTo(px, y + h / 2 + 3); } c.stroke();
  c.restore();
}
function waveScope(c, x, y, w, h, o = {}) {
  const t0 = o.t0 ?? 12.34, win = o.win ?? 0.045, n = o.n ?? 320, g = o.gain ?? 0.9;
  if (o.grid !== false) graticule(c, x, y, w, h, o.gridCol ?? 'orange');
  c.save(); c.strokeStyle = o.col ?? rgba('amber', 1); c.lineWidth = o.lw ?? 1.6; c.lineJoin = 'round';
  if (o.glow) { c.shadowColor = c.strokeStyle; c.shadowBlur = o.glow; }
  c.beginPath();
  for (let i = 0; i <= n; i++) {
    const v = (o.fn ?? synthWave)(t0 + (win * i) / n, o.seed ?? 1);
    const px = x + (w * i) / n, py = y + h / 2 - clamp(v * g, -1, 1) * h * 0.46;
    if (i) c.lineTo(px, py); else c.moveTo(px, py);
  }
  c.stroke(); c.restore();
}

/** header strip (atfield-kit): solid slanted tab with title knocked out + rule + right caption */
function headerStrip(c, x, y, w, o) {
  const col = o.color ?? rgba('orange', 1), h = 34;
  c.save();
  c.font = mono(700, 17); c.letterSpacing = '3px'; const tw = c.measureText(o.tag).width; c.letterSpacing = '0px';
  c.font = jp(19, 700, false); const jw = o.tagJp ? c.measureText(o.tagJp).width + 18 : 0;
  const bw = tw + jw + 44;
  c.fillStyle = col;
  c.beginPath(); c.moveTo(x, y); c.lineTo(x + bw, y); c.lineTo(x + bw + h * 0.7, y + h); c.lineTo(x, y + h); c.closePath(); c.fill();
  c.fillStyle = rgba('ink', 1); c.textBaseline = 'middle';
  c.font = mono(700, 17); c.letterSpacing = '3px'; c.fillText(o.tag, x + 14, y + h / 2 + 1); c.letterSpacing = '0px';
  if (o.tagJp) { c.font = jp(19, 700, false); c.fillText(o.tagJp, x + 14 + tw + 14, y + h / 2 + 1); }
  c.fillStyle = col;
  c.fillRect(x + bw + h * 0.7 + 8, y + h - 2, w - bw - h * 0.7 - 8, 2);
  c.fillRect(x + w - 60, y + h - 8, 60, 6);
  if (o.sub) { c.font = mono(500, 13); c.letterSpacing = '2.5px'; c.textBaseline = 'alphabetic'; c.fillText(o.sub, x + bw + h * 0.7 + 18, y + h - 10); }
  if (o.right || o.rightJp) {
    c.textAlign = 'right'; c.textBaseline = 'alphabetic';
    let rx = x + w - 72;
    if (o.rightJp) { c.font = jp(22, 700, true); c.letterSpacing = '0px'; c.fillText(o.rightJp, rx, y + h - 10); rx -= c.measureText(o.rightJp).width + 16; }
    if (o.right) { c.font = mono(600, 13); c.letterSpacing = '2.5px'; c.fillText(o.right, rx, y + h - 10); }
  }
  c.restore();
}

/** MAGI-style chrome: number tab, title + JP, ruled line, 7-seg clock; footer rule + ticker. */
function chrome(c, o) {
  const col = o.color ?? rgba('orange', 1), X0 = o.x0 ?? 56, X1 = o.x1 ?? W - 56, Y = o.y ?? 64, FY = o.fy ?? H - 52;
  c.save();
  c.fillStyle = col;
  chamferPath(c, X0, Y, 78, 52, [0, 16, 0, 0]); c.fill();
  c.fillStyle = rgba('ink', 1); c.font = mono(700, 30); c.textBaseline = 'middle'; c.textAlign = 'center';
  c.fillText(o.no, X0 + 36, Y + 28);
  c.textAlign = 'left'; c.textBaseline = 'alphabetic'; c.fillStyle = col;
  c.font = mono(700, 22); c.letterSpacing = '5px'; c.fillText(o.en, X0 + 96, Y + 26);
  const tw = c.measureText(o.en).width; c.letterSpacing = '0px';
  c.font = jp(22, 700, false); c.fillText(o.jpText, X0 + 96 + tw + 18, Y + 26);
  if (o.sub) { c.font = mono(500, 12); c.letterSpacing = '2.4px'; c.globalAlpha = 0.75; c.fillText(o.sub, X0 + 96, Y + 48); c.globalAlpha = 1; c.letterSpacing = '0px'; }
  c.fillRect(X0, Y + 66, X1 - X0, 2);
  c.globalAlpha = 0.6;
  for (let x = X0; x <= X1; x += 24) c.fillRect(x, Y + 68, 1, (x - X0) % 120 === 0 ? 8 : 4);
  c.globalAlpha = 1;
  const tc = o.clock ?? '00:12.34';
  const w7 = segWidth(tc, 30, 3.6);
  sevenSeg(c, tc, X1 - w7, Y + 6, 30, col, rgba('orange', 0.08), { thick: 3.6 });
  c.font = mono(600, 12); c.letterSpacing = '2.4px'; c.textAlign = 'right';
  c.fillText(o.barText ?? 'BAR 004  BEAT 3  133.33 BPM', X1 - w7 - 24, Y + 24);
  c.font = jp(13, 600, false); c.letterSpacing = '0px';
  c.fillText('経過時間  小節  拍', X1 - w7 - 24, Y + 46);
  const beat = o.beat ?? 3;
  for (let i = 0; i < 4; i++) { c.globalAlpha = i + 1 === beat ? 1 : 0.18; c.fillRect(X1 - w7 - 24 - 150 + i * 18, Y + 52, 12, 5); }
  c.globalAlpha = 1; c.textAlign = 'left';
  // footer
  c.fillRect(X0, FY - 8, X1 - X0, 1);
  if (o.tick) ticker(c, X0 + 250, FY + 18, X1 - X0 - 250, o.tick, o.tickOff ?? 137, { color: rgba('orange', 0.6), size: 12 });
  c.fillStyle = col;
  chamferPath(c, X0, FY, 230, 26, [0, 0, 10, 0]); c.fill();
  c.fillStyle = rgba('ink', 1); c.font = mono(700, 12); c.letterSpacing = '2px'; c.textBaseline = 'middle';
  c.fillText(o.foot ?? 'NERV HQ  中央作戦室', X0 + 10, FY + 14);
  c.restore();
}

/** dim hex ground (magi-hud makeHexGround in Canvas2D) */
function hexGround(c, r = 38, a = 0.055, seed = 7, col = 'orange') {
  c.save();
  const p = new Path2D(), hot = new Path2D();
  hexGrid(-r, -r, W + 2 * r, H + 2 * r, r, (cx, cy, ci, ri) => {
    const pts = [];
    for (let i = 0; i < 6; i++) { const an = Math.PI / 6 + (i * TAU) / 6; pts.push([cx + r * Math.cos(an), cy + r * Math.sin(an)]); }
    pts.forEach(([x, y], i) => (i ? p.lineTo(x, y) : p.moveTo(x, y))); p.closePath();
    if (hash(ci, ri, seed) > 0.985) { pts.forEach(([x, y], i) => { const X = cx + (x - cx) * 0.8, Y = cy + (y - cy) * 0.8; i ? hot.lineTo(X, Y) : hot.moveTo(X, Y); }); hot.closePath(); }
  });
  // radial falloff: draw twice, with a clip ellipse for the brighter centre
  c.strokeStyle = rgba(col, a * 0.6); c.lineWidth = 1; c.stroke(p);
  c.fillStyle = rgba(col, a * 0.5); c.fill(hot);
  c.beginPath(); c.ellipse(W / 2, H / 2, W * 0.45, H * 0.42, 0, 0, TAU); c.clip();
  c.strokeStyle = rgba(col, a * 0.5); c.stroke(p);
  c.restore();
}

// ---------------------------------------------------------------- post: bloom + CRT
/**
 * The video's finishing: bloom on the brightest orange (threshold on max channel), tone shoulder,
 * CRT scanlines (every 3 logical px of the 1080 video = 4 px here) + RGB phosphor mask, vignette, grain.
 */
function post(cv, o = {}) {
  const bloom = o.bloom ?? 0.6, thr = o.threshold ?? 0.62, knee = 0.25, scan = o.scan ?? 0.24, vig = o.vignette ?? 0.42, grain = o.grain ?? 0.035;
  const c = cv.getContext('2d');
  c.setTransform(1, 0, 0, 1, 0, 0);
  // ---- bloom pyramid (quarter res)
  const bw = OUT_W / 4, bh = OUT_H / 4;
  const b0 = document.createElement('canvas'); b0.width = bw; b0.height = bh;
  const bc = b0.getContext('2d', { willReadFrequently: true });
  bc.imageSmoothingQuality = 'high';
  bc.drawImage(cv, 0, 0, bw, bh);
  const id = bc.getImageData(0, 0, bw, bh), d = id.data;
  for (let i = 0; i < d.length; i += 4) {
    const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
    const l = Math.max(r, g, b);
    let rq = clamp(l - thr + knee, 0, 2 * knee); rq = (rq * rq) / (4 * knee + 1e-5);
    const w = Math.max(rq, l - thr) / Math.max(l, 1e-5);
    d[i] *= w; d[i + 1] *= w; d[i + 2] *= w;
  }
  bc.putImageData(id, 0, 0);
  const acc = document.createElement('canvas'); acc.width = bw; acc.height = bh;
  const ac = acc.getContext('2d');
  ac.globalCompositeOperation = 'lighter';
  [[2, 0.5], [6, 0.45], [16, 0.4], [40, 0.35]].forEach(([r, k]) => { ac.filter = `blur(${r}px)`; ac.globalAlpha = k; ac.drawImage(b0, 0, 0); });
  c.save();
  c.globalCompositeOperation = 'lighter'; c.globalAlpha = bloom; c.imageSmoothingQuality = 'high';
  c.drawImage(acc, 0, 0, OUT_W, OUT_H);
  if (o.halation) { c.globalAlpha = o.halation; c.filter = 'blur(6px)'; c.drawImage(acc, 0, 0, OUT_W, OUT_H); }
  c.restore();
  // ---- per-pixel: shoulder, scanlines, phosphor mask, vignette, grain
  const img = c.getImageData(0, 0, OUT_W, OUT_H), p = img.data;
  const period = 4; // physical px per scanline
  const lineK = new Float32Array(period);
  for (let y = 0; y < period; y++) { const line = 0.5 + 0.5 * Math.cos(((y + 0.5) * TAU) / period); lineK[y] = 1 - scan * (1 - line) * 0.9; }
  let seed = 1234567;
  const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
  for (let y = 0; y < OUT_H; y++) {
    const lk = lineK[y % period];
    const dy = (y / OUT_H - 0.5) * 0.8;
    for (let x = 0; x < OUT_W; x++) {
      const i = (y * OUT_W + x) * 4;
      const len = Math.hypot(x / OUT_W - 0.5, dy);
      const v = 1 - vig * (1 - smoothstep(0.95, 0.25, len));
      const col = x % 3;
      const g = (rnd() - 0.5) * grain * 255;
      for (let k = 0; k < 3; k++) {
        let val = p[i + k] / 255;
        const m = lk * (1 - scan * 0.12 * (k !== col ? 1 : 0));
        val = val * m * v;
        p[i + k] = clamp(val * 255 + g * (0.3 + val), 0, 255);
      }
    }
  }
  c.putImageData(img, 0, 0);
}

/** boot: load fonts, draw, post, mark done */
async function run(draw, postOpts) {
  await loadFonts();
  await new Promise((r) => setTimeout(r, 50));
  const { cv, c } = makeCanvas();
  draw(c);
  if (postOpts !== false) post(cv, postOpts || {});
  document.title = 'done';
}
