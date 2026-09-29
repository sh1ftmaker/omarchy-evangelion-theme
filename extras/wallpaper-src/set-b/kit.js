// NERV HQ terminal kit, ported from evangelion/app/src/scenes/_eva.ts to plain JS.
// Draw in logical px (W x H), the canvas is rendered at DPR x.
'use strict';

const HEX = {
  ink: '#050403', ink2: '#120C06', graphite: '#4A3218', ash: '#9C6A2E', bone: '#FFE9C8', metal: '#C8B8A0',
  orange: '#FF7A00', amber: '#FFB000', red: '#FF1A1A', blood: '#6A0000', green: '#39FF6A', cyan: '#00C8FF',
  purple: '#7A3CFF', lime: '#B6FF00',
};
const TAU = Math.PI * 2;
const hexRGB = (k) => { const n = parseInt((HEX[k] ?? k).replace('#', ''), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
function rgba(key, a = 1) { const [r, g, b] = hexRGB(key); return `rgba(${r},${g},${b},${a})`; }
function mix(a, b, k, alpha = 1) {
  const A = hexRGB(a), B = hexRGB(b), u = Math.max(0, Math.min(1, k));
  return `rgba(${Math.round(A[0] + (B[0] - A[0]) * u)},${Math.round(A[1] + (B[1] - A[1]) * u)},${Math.round(A[2] + (B[2] - A[2]) * u)},${alpha})`;
}
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));

// deterministic hash / rng
function hash(...xs) {
  let h = 2166136261 >>> 0;
  for (const x of xs) { h ^= Math.floor(x * 1000003) >>> 0; h = Math.imul(h, 16777619) >>> 0; h ^= h >>> 13; h = Math.imul(h, 0x5bd1e995) >>> 0; h ^= h >>> 15; }
  return (h >>> 0) / 4294967296;
}
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
// smooth 1D value noise
function vnoise(x, seed = 0) { const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return hash(i, seed) * (1 - u) + hash(i + 1, seed) * u; }
function fbm(x, seed = 0) { let v = 0, a = 0.5, fr = 1; for (let o = 0; o < 5; o++) { v += a * vnoise(x * fr, seed + o * 17); fr *= 2; a *= 0.5; } return v; }

// ---------------------------------------------------------------- type
const MONO = '"Plex Mono", "IBM Plex Mono", monospace';
const SERIF = '"Corm", "Cormorant Garamond", serif';
const JP_SERIF = '"Noto Serif CJK JP", serif';
const JP_SANS = '"Noto Sans CJK JP", sans-serif';
const mono = (w, px) => `${w} ${px}px ${MONO}`;
const jp = (px, weight = 600, serif = true) => `${weight} ${px}px ${serif ? JP_SERIF : JP_SANS}`;

function condensed(c, text, x, y, size, o = {}) {
  const sx = o.sx ?? 0.62;
  c.save();
  c.font = `${o.weight ?? 600} ${size}px ${SERIF}`;
  c.letterSpacing = `${o.tracking ?? 0}px`;
  c.textBaseline = 'alphabetic';
  const w = c.measureText(text).width * sx;
  const al = o.align ?? 'left';
  const x0 = al === 'center' ? x - w / 2 : al === 'right' ? x - w : x;
  c.translate(x0, y); c.scale(sx, 1); c.textAlign = 'left';
  c.fillStyle = o.color ?? rgba('bone');
  if (o.glow) { c.shadowColor = c.fillStyle; c.shadowBlur = o.glow; }
  c.fillText(text, 0, 0);
  const bd = o.bold ?? 0.022;
  if (bd > 0) { c.strokeStyle = c.fillStyle; c.lineWidth = size * bd; c.lineJoin = 'miter'; c.strokeText(text, 0, 0); }
  c.restore();
  return w;
}
function evaTitle(c, x, y, lines, o = {}) {
  let yy = y;
  lines.forEach(([txt, size, sx]) => { yy += size * (o.lead ?? 0.86); condensed(c, txt, x, yy, size, { sx: sx ?? 0.6, color: o.color, align: o.align }); });
  return yy;
}
function evaLabel(c, x, y, en, jpText, o = {}) {
  const s = o.size ?? 1;
  c.save();
  c.globalAlpha *= o.alpha ?? 1;
  c.textAlign = o.align ?? 'left'; c.textBaseline = 'alphabetic';
  c.fillStyle = o.color ?? rgba('orange');
  c.font = mono(600, 13 * s); c.letterSpacing = `${2.4 * s}px`;
  c.fillText(en.toUpperCase(), x, y);
  c.letterSpacing = '0px';
  if (jpText) { c.font = jp(15 * s, 600, false); c.fillText(jpText, x, y + 20 * s); }
  c.restore();
}
function text(c, s, x, y, o = {}) {
  c.save();
  c.font = o.font ?? mono(o.weight ?? 500, o.size ?? 12);
  c.letterSpacing = `${o.track ?? 1.5}px`;
  c.fillStyle = o.color ?? rgba('orange');
  c.textAlign = o.align ?? 'left'; c.textBaseline = o.base ?? 'alphabetic';
  if (o.glow) { c.shadowColor = c.fillStyle; c.shadowBlur = o.glow; }
  c.fillText(s, x, y);
  const w = c.measureText(s).width;
  c.restore();
  return w;
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
  const col = o.color ?? rgba('orange'), cut = o.cut ?? 12, hh = o.title ? (o.header ?? 20) : 0;
  c.save();
  c.globalAlpha *= o.alpha ?? 1;
  chamferPath(c, x, y, w, h, [0, cut, 0, cut]);
  c.fillStyle = o.fill ?? 'rgba(18,12,6,0.78)'; c.fill();
  c.strokeStyle = col; c.lineWidth = o.lw ?? 1.2; c.stroke();
  if (o.title) {
    const ts = o.tsize ?? 10.5;
    c.font = mono(700, ts); c.letterSpacing = '1.6px';
    const tw = c.measureText(o.title.toUpperCase()).width;
    c.font = jp(ts + 1, 700, false);
    const jw = o.jp ? c.measureText(o.jp).width + 10 : 0;
    c.fillStyle = col;
    chamferPath(c, x, y, Math.min(w * 0.8, 20 + tw + jw + hh * 0.6), hh, [0, hh * 0.6, 0, 0]); c.fill();
    c.fillStyle = o.tcol ?? rgba('ink');
    c.font = mono(700, ts); c.letterSpacing = '1.6px'; c.textBaseline = 'middle';
    c.fillText(o.title.toUpperCase(), x + 8, y + hh / 2 + 1);
    c.letterSpacing = '0px';
    if (o.jp) { c.font = jp(ts + 1, 700, false); c.fillText(o.jp, x + 16 + tw, y + hh / 2 + 1); }
    c.strokeStyle = col; c.globalAlpha *= 0.5; c.lineWidth = 0.8;
    c.beginPath(); c.moveTo(x + 4, y + hh + 3); c.lineTo(x + w - 4, y + hh + 3); c.stroke();
  }
  c.restore();
  return { x: x + 8, y: y + hh + 9, w: w - 16, h: h - hh - 16 };
}
function brackets(c, x, y, w, h, len = 14, color = rgba('orange'), lw = 1.5) {
  c.save();
  c.strokeStyle = color; c.lineWidth = lw; c.lineCap = 'square';
  c.beginPath();
  c.moveTo(x, y + len); c.lineTo(x, y); c.lineTo(x + len, y);
  c.moveTo(x + w - len, y); c.lineTo(x + w, y); c.lineTo(x + w, y + len);
  c.moveTo(x + w, y + h - len); c.lineTo(x + w, y + h); c.lineTo(x + w - len, y + h);
  c.moveTo(x + len, y + h); c.lineTo(x, y + h); c.lineTo(x, y + h - len);
  c.stroke(); c.restore();
}
function hexPath(c, cx, cy, r, rot = 0) {
  c.beginPath();
  for (let i = 0; i < 6; i++) { const a = rot + Math.PI / 6 + (i * TAU) / 6; const px = cx + r * Math.cos(a), py = cy + r * Math.sin(a); if (i === 0) c.moveTo(px, py); else c.lineTo(px, py); }
  c.closePath();
}
function hexGrid(x, y, w, h, r, fn) {
  const dx = Math.sqrt(3) * r, dy = 1.5 * r; let i = 0;
  for (let row = 0; y + row * dy <= y + h + r; row++) for (let col = 0; x + col * dx <= x + w + dx; col++) fn(x + col * dx + (row % 2 ? dx / 2 : 0), y + row * dy, col, row, i++);
}
function octPath(c, cx, cy, r) {
  c.beginPath();
  for (let i = 0; i < 8; i++) { const a = Math.PI / 8 + (i * TAU) / 8; const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r; if (i) c.lineTo(x, y); else c.moveTo(x, y); }
  c.closePath();
}
function hazard(c, x, y, w, h, phase = 0, a = rgba('red'), b = null, stripe = 18) {
  c.save();
  c.beginPath(); c.rect(x, y, w, h); c.clip();
  if (b) { c.fillStyle = b; c.fillRect(x, y, w, h); }
  c.fillStyle = a;
  const p = ((phase % (stripe * 2)) + stripe * 2) % (stripe * 2);
  for (let sx = x - h - stripe * 2 + p; sx < x + w + stripe; sx += stripe * 2) {
    c.beginPath(); c.moveTo(sx, y + h); c.lineTo(sx + h, y); c.lineTo(sx + h + stripe, y); c.lineTo(sx + stripe, y + h); c.closePath(); c.fill();
  }
  c.restore();
}

// ---------------------------------------------------------------- instruments
const SEG = {
  '0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg',
  '-': 'g', ' ': '', A: 'abcefg', E: 'adefg', F: 'aefg', H: 'bcefg', L: 'def', P: 'abefg', r: 'eg', o: 'cdeg', U: 'bcdef', n: 'ceg', t: 'defg', d: 'bcdeg', b: 'cdefg', C: 'adef', S: 'acdfg',
};
function sevenSeg(c, txt, x, y, h, color = rgba('orange'), dim = rgba('orange', 0.08), o = {}) {
  const w = h * (o.wr ?? 0.52), t = o.thick ?? h * 0.11, sk = o.skew ?? 0.1, gap = t * 0.18;
  let cx = x;
  c.save();
  const seg = (on, pts) => {
    if (!on && !dim) return;
    c.fillStyle = on ? color : dim;
    if (on && o.glow) { c.shadowColor = color; c.shadowBlur = o.glow; } else c.shadowBlur = 0;
    c.beginPath();
    pts.forEach(([px, py], i) => { const X = cx + px + (h - py) * sk, Y = y + py; if (i) c.lineTo(X, Y); else c.moveTo(X, Y); });
    c.closePath(); c.fill();
  };
  for (const ch of txt) {
    if (ch === ':' || ch === '.') {
      c.fillStyle = color;
      if (o.glow) { c.shadowColor = color; c.shadowBlur = o.glow; }
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
function segMeter(c, x, y, w, h, n, v, o = {}) {
  const g = o.gap ?? 1.5, lit = v * n;
  c.save();
  for (let i = 0; i < n; i++) {
    const k = i / n;
    const col = k >= (o.hotFrom ?? 0.8) ? (o.hot ?? rgba('red')) : (o.color ?? rgba('orange'));
    const on = i < Math.floor(lit) ? 1 : i < lit ? lit - i : 0;
    c.fillStyle = on > 0 ? col : (o.dim ?? rgba('orange', 0.1));
    c.globalAlpha = on > 0 ? 0.35 + 0.65 * on : 1;
    if (o.vertical) { const bh = (h - g * (n - 1)) / n; c.fillRect(x, y + h - (i + 1) * bh - i * g, w, bh); }
    else { const bw = (w - g * (n - 1)) / n; c.fillRect(x + i * (bw + g), y, bw, h); }
  }
  c.restore();
}
function scale(c, x0, y0, x1, y1, n, o = {}) {
  const dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy), nx = (dy / L) * (o.side ?? 1), ny = (-dx / L) * (o.side ?? 1), tk = o.tick ?? 4, mj = o.major ?? 5;
  c.save();
  c.strokeStyle = o.color ?? rgba('orange', 0.8); c.fillStyle = o.color ?? rgba('orange', 0.8); c.lineWidth = 0.8;
  c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, y1);
  for (let i = 0; i <= n; i++) { const px = x0 + (dx * i) / n, py = y0 + (dy * i) / n, len = i % mj === 0 ? tk * 1.8 : tk; c.moveTo(px, py); c.lineTo(px + nx * len, py + ny * len); }
  c.stroke();
  if (o.label) {
    c.font = mono(500, 8); c.textAlign = 'center'; c.textBaseline = 'middle';
    for (let i = 0; i <= n; i += mj) { const s = o.label(i); if (s) c.fillText(s, x0 + (dx * i) / n + nx * (tk * 1.8 + 8), y0 + (dy * i) / n + ny * (tk * 1.8 + 8)); }
  }
  c.restore();
}
function warningBox(c, x, y, w, h, word, jpText, o = {}) {
  const col = o.color ?? rgba('red'), bl = o.blink ?? 1;
  c.save();
  chamferPath(c, x, y, w, h, 14);
  c.fillStyle = o.fill ?? `rgba(40,0,0,${0.55 + 0.35 * bl})`; c.fill();
  c.strokeStyle = col; c.lineWidth = 2.5; c.stroke();
  const band = h * 0.12;
  hazard(c, x + 8, y + 8, w - 16, band, o.phase ?? 0, col, null, band * 1.1);
  hazard(c, x + 8, y + h - 8 - band, w - 16, band, -(o.phase ?? 0), col, null, band * 1.1);
  condensed(c, word, x + w / 2, y + h * (o.wy ?? 0.64), h * (o.ws ?? 0.46), { sx: 0.58, color: o.wcol ?? col, align: 'center', glow: o.glow });
  c.font = jp(h * 0.11, 700, false); c.fillStyle = o.wcol ?? col; c.textAlign = 'center';
  c.fillText(jpText, x + w / 2, y + h * 0.79);
  c.restore();
}
// frozen ticker: text repeated, clipped, offset by phase
function ticker(c, x, y, w, txt, phase = 0, o = {}) {
  const size = o.size ?? 10;
  c.save();
  c.beginPath(); c.rect(x, y - size - 3, w, size + 8); c.clip();
  c.font = mono(o.weight ?? 500, size); c.fillStyle = o.color ?? rgba('orange', 0.85); c.letterSpacing = '1.6px'; c.textBaseline = 'alphabetic';
  const tw = c.measureText(txt + '   ').width;
  for (let off = -(phase % tw); off < w; off += tw) c.fillText(txt + '   ', x + off, y);
  c.restore();
}
function hexData(seed, step, n = 8) { let s = ''; for (let i = 0; i < n; i++) s += Math.floor(hash(seed, step, i) * 16).toString(16).toUpperCase(); return s; }

// ---------------------------------------------------------------- post: bloom, glitch rows, CRT
// glitches: [{y, h, dx, split}] in logical px.
function post(canvas, o = {}) {
  const W = canvas.width, H = canvas.height, c = canvas.getContext('2d', { willReadFrequently: true });
  c.setTransform(1, 0, 0, 1, 0, 0);
  const D = W / (o.W ?? 1280);
  // glitch rows with RGB split
  if (o.glitches && o.glitches.length) {
    const src = c.getImageData(0, 0, W, H), s = src.data, out = c.getImageData(0, 0, W, H), d = out.data;
    for (const g of o.glitches) {
      const y0 = Math.max(0, Math.round(g.y * D)), y1 = Math.min(H, Math.round((g.y + g.h) * D));
      const dx = Math.round(g.dx * D), sp = Math.round((g.split ?? 4) * D);
      for (let y = y0; y < y1; y++) for (let x = 0; x < W; x++) {
        const i = (y * W + x) * 4;
        const xr = Math.min(W - 1, Math.max(0, x - dx + sp)), xg = Math.min(W - 1, Math.max(0, x - dx)), xb = Math.min(W - 1, Math.max(0, x - dx - sp));
        d[i] = s[(y * W + xr) * 4]; d[i + 1] = s[(y * W + xg) * 4 + 1]; d[i + 2] = s[(y * W + xb) * 4 + 2];
      }
    }
    c.putImageData(out, 0, 0);
  }
  // global chromatic aberration (subtle)
  const ca = (o.ca ?? 1.2) * D;
  if (ca > 0.5) {
    const tmp = document.createElement('canvas'); tmp.width = W; tmp.height = H;
    const t = tmp.getContext('2d'); t.drawImage(canvas, 0, 0);
    const img = c.getImageData(0, 0, W, H), d = img.data, s = t.getImageData(0, 0, W, H).data, off = Math.round(ca);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4, xr = Math.min(W - 1, x + off), xb = Math.max(0, x - off);
      d[i] = s[(y * W + xr) * 4]; d[i + 2] = s[(y * W + xb) * 4 + 2];
    }
    c.putImageData(img, 0, 0);
  }
  // bloom: threshold at 1/4 res, blur, add
  const q = 4, bw = W / q, bh = H / q;
  const b = document.createElement('canvas'); b.width = bw; b.height = bh;
  const bc = b.getContext('2d'); bc.drawImage(canvas, 0, 0, bw, bh);
  const bi = bc.getImageData(0, 0, bw, bh), bd = bi.data, th = (o.threshold ?? 0.5) * 255;
  for (let i = 0; i < bd.length; i += 4) {
    const l = Math.max(bd[i], bd[i + 1], bd[i + 2]);
    const k = l > th ? (l - th) / (255 - th) : 0;
    bd[i] *= k; bd[i + 1] *= k; bd[i + 2] *= k;
  }
  bc.putImageData(bi, 0, 0);
  c.save();
  c.globalCompositeOperation = 'lighter';
  for (const [r, a] of [[5, 0.28], [14, 0.3], [36, 0.22]]) {
    c.filter = `blur(${r * D / q * q}px)`;
    c.globalAlpha = a * (o.bloom ?? 1);
    c.drawImage(b, 0, 0, W, H);
  }
  c.restore();
  c.filter = 'none';
  // CRT: scanlines + phosphor mask + vignette + grain
  const img = c.getImageData(0, 0, W, H), d = img.data, k = o.scan ?? 0.24, per = o.period ?? 4, vig = o.vignette ?? 0.38;
  const R = rng(o.seed ?? 7);
  for (let y = 0; y < H; y++) {
    const line = 0.5 + 0.5 * Math.cos((y * TAU) / per);
    const m = 1 - k * (1 - line) * 0.9;
    const vy = (y / H - 0.5) * 2;
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4, col = x % 3;
      const vx = (x / W - 0.5) * 2;
      const v = 1 - vig * Math.pow(Math.min(1, (vx * vx * 0.7 + vy * vy) * 0.55), 1.5);
      const gr = 1 + (R() - 0.5) * (o.grain ?? 0.06);
      const f = m * v * gr;
      d[i] = d[i] * f * (col === 0 ? 1 : 1 - k * 0.12);
      d[i + 1] = d[i + 1] * f * (col === 1 ? 1 : 1 - k * 0.12);
      d[i + 2] = d[i + 2] * f * (col === 2 ? 1 : 1 - k * 0.12);
    }
  }
  c.putImageData(img, 0, 0);
}

// ---------------------------------------------------------------- boot
async function boot(draw, o = {}) {
  const W = o.W ?? 1280, H = o.H ?? 800, D = o.D ?? 2;
  const cv = document.getElementById('c');
  cv.width = W * D; cv.height = H * D;
  cv.style.width = W * D + 'px'; cv.style.height = H * D + 'px';
  await Promise.all([
    document.fonts.load(`600 40px "Corm"`), document.fonts.load(`500 12px "Plex Mono"`), document.fonts.load(`600 12px "Plex Mono"`), document.fonts.load(`700 12px "Plex Mono"`),
    document.fonts.load(`700 20px "Noto Sans CJK JP"`, '緊急事態解析中'), document.fonts.load(`900 20px "Noto Serif CJK JP"`, '暴走'),
  ]);
  await new Promise((r) => setTimeout(r, 300));
  const c = cv.getContext('2d', { willReadFrequently: true });
  c.setTransform(D, 0, 0, D, 0, 0);
  if (!o.transparent) { c.fillStyle = rgba('ink'); c.fillRect(0, 0, W, H); }
  const po = draw(c, W, H) || {};
  if (!o.transparent) post(cv, Object.assign({ W }, po));
  document.title = 'done';
}
