// 8 — BERSERK: Unit-01 berserker HUD, frozen on a kick (drop 3).
boot((c, W, H) => {
  const CX = 812, CY = 352, R = 246;
  const P = (a = 1) => rgba('purple', a), LI = (a = 1) => rgba('lime', a), RD = (a = 1) => rgba('red', a);
  const mel = (b) => clamp(0.5 + 0.45 * Math.exp(-b / 16) + 0.9 * (fbm(b * 0.3, 31) - 0.5) + (b > 30 && b < 36 ? 0.2 : 0));

  // ---------------- polar hex spectrum (explodes outward from the core, mirrored)
  const r = 13;
  hexGrid(CX - 700, CY - 520, 1400, 1040, r, (x, y, col, row) => {
    const dx = x - CX, dy = y - CY, d = Math.hypot(dx, dy);
    const a = Math.acos(clamp(dy / Math.max(d, 1e-3), -1, 1)); // 0 = straight down
    const band = 1 + (a / Math.PI) * 56;
    const lev = clamp((mel(band) - 0.15) / 0.85);
    const Rin = 62, Rout = Rin + lev * 172;
    const h = hash(col, row, 1);
    const fall = 1 - clamp((d - 120) / 560);
    // idle grid
    hexPath(c, x, y, r - 0.8); c.strokeStyle = P(0.13 * fall); c.lineWidth = 0.6; c.stroke();
    if (d > Rin && d < Rout) {
      const k = clamp((d - Rin) / 230), rim = d > Rout - 1.3 * r;
      hexPath(c, x, y, r - 2);
      c.fillStyle = rim ? LI(0.95) : mix('purple', 'red', k * 1.2, 0.45 + 0.4 * h);
      c.fill();
    }
    // kick shockwave ring
    const sw = Math.exp(-Math.abs(d - 292) / 12);
    if (sw > 0.2 && h > 0.35) { hexPath(c, x, y, r - 2); c.fillStyle = h > 0.88 ? rgba('bone', 0.8 * sw) : RD(0.75 * sw); c.fill(); }
    // clap: scattered red-hot cells
    if (h < 0.05 && d < 240 && hash(col, row, 7) > 0.5) { hexPath(c, x, y, r - 2); c.fillStyle = RD(0.7); c.fill(); }
    if (hash(col, row, 9) > 0.992 && fall > 0) { hexPath(c, x, y, r - 3); c.fillStyle = LI(0.5 * fall); c.fill(); }
  });

  // ---------------- left: kanji + card
  c.save();
  c.font = jp(250, 900, true); c.fillStyle = RD(); c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText('暴走', 292, 318);
  c.restore();
  evaLabel(c, 58, 96, 'evangelion unit-01 // status', 'エヴァンゲリオン初号機  状態', { color: LI(0.9), size: 0.9 });
  c.fillStyle = RD(); chamferPath(c, 58, 134, 176, 22, [0, 10, 0, 0]); c.fill();
  text(c, 'MODE: BERSERK', 66, 150, { weight: 700, size: 11, color: rgba('ink'), track: 2.5 });
  c.fillStyle = RD(); c.fillRect(244, 137, 15, 15);
  c.font = jp(15, 900, false); c.fillStyle = RD(0.95); c.fillText('制御不能', 268, 151);
  const bw = condensed(c, 'BERSERK', 52, 610, 178, { sx: 0.55, color: LI(), bold: 0.03, glow: 14 });
  c.fillStyle = LI(); c.fillRect(58, 626, bw - 6, 2.5);
  text(c, 'PHASE 04/09   EVA-01 TEST TYPE', 58, 644, { weight: 600, size: 10, color: LI(), track: 2 });
  c.font = jp(12, 600, false); c.fillStyle = LI(); c.textAlign = 'right'; c.fillText('試験初号機', 52 + bw, 644); c.textAlign = 'left';

  // ---------------- the ring
  c.save(); c.translate(CX, CY);
  c.strokeStyle = P(0.95); c.lineWidth = 1.3; c.beginPath(); c.arc(0, 0, R, 0, TAU); c.stroke();
  c.strokeStyle = P(0.45); c.lineWidth = 0.8; c.beginPath(); c.arc(0, 0, R - 12, 0, TAU); c.stroke();
  for (let i = 0; i < 144; i++) {
    const a = (i / 144) * TAU - Math.PI / 2, maj = i % 12 === 0, near = ((i - 37 + 144) % 144) < 10;
    const len = maj ? 11 : 5;
    c.strokeStyle = near ? LI(0.95) : P(maj ? 0.95 : 0.5); c.lineWidth = maj ? 1.6 : 0.8;
    c.beginPath(); c.moveTo(Math.cos(a) * R, Math.sin(a) * R); c.lineTo(Math.cos(a) * (R + len), Math.sin(a) * (R + len)); c.stroke();
  }
  c.font = mono(500, 8.5); c.fillStyle = P(0.9); c.textAlign = 'center'; c.textBaseline = 'middle';
  for (let i = 0; i < 12; i++) { const a = (i / 12) * TAU - Math.PI / 2; c.fillText(String(i * 30).padStart(3, '0'), Math.cos(a) * (R + 22), Math.sin(a) * (R + 22)); }
  c.strokeStyle = RD(0.95); c.lineWidth = 4; c.shadowColor = RD(); c.shadowBlur = 10;
  for (let k = 0; k < 3; k++) { const a0 = 0.7 + (k * TAU) / 3; c.beginPath(); c.arc(0, 0, R - 6, a0, a0 + 0.48); c.stroke(); }
  c.shadowBlur = 0;
  c.strokeStyle = P(0.6); c.lineWidth = 0.8;
  for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { c.beginPath(); c.moveTo(dx * (R + 32), dy * (R + 32)); c.lineTo(dx * (R + 50), dy * (R + 50)); c.stroke(); }
  octPath(c, 0, 0, 58); c.fillStyle = 'rgba(8,4,14,0.92)'; c.fill(); c.strokeStyle = P(); c.lineWidth = 1.6; c.stroke();
  c.restore();
  sevenSeg(c, '400', CX - 38, CY - 26, 36, LI(), LI(0.07), { glow: 14 });
  text(c, 'SYNC %', CX, CY + 26, { weight: 700, size: 9, color: P(), align: 'center', track: 1.5 });
  c.font = jp(11, 700, false); c.fillStyle = P(); c.textAlign = 'center'; c.fillText('同調率', CX, CY + 40); c.textAlign = 'left';
  text(c, '16 kHz', CX, CY - R - 40, { size: 8.5, color: P(0.85), align: 'center' });
  text(c, '30 Hz', CX, CY + R + 44, { size: 8.5, color: P(0.85), align: 'center' });
  evaLabel(c, CX - R - 10, CY - R + 4, 'harmonic field', '調和場 暴走', { color: P(), size: 0.8 });
  // the giant sync callout
  const sx = CX + 176, sy = CY + 192;
  condensed(c, '400%', sx, sy + 70, 84, { sx: 0.58, color: LI(), glow: 16 });
  c.font = jp(14, 900, false); c.fillStyle = LI(); c.fillText('同調率  限界突破', sx + 2, sy + 90);

  // ---------------- top band
  hazard(c, 0, 0, W, 30, 4, RD(), rgba('ink'), 16);
  c.fillStyle = rgba('ink'); c.fillRect(0, 30, W, 28);
  c.fillStyle = RD(); c.fillRect(0, 30, W, 1.2); c.fillRect(0, 57, W, 1.2);
  c.fillStyle = RD(); c.fillRect(0, 32, 800, 24);
  ticker(c, 8, 49, 790, 'ACTIVITY LIMIT EXCEEDED // 活動限界突破 // UNIT-01 BERSERK // 暴走 // SYNC RATIO 400% // PILOT CONTROL LOST //', 0, { size: 11, weight: 700, color: rgba('ink') });
  ticker(c, 812, 49, W - 820, 'NEURAL LINK REVERSED // 神経接続逆流 // LIMITER RELEASED // リミッター解除 //', 90, { size: 11, weight: 700, color: RD() });

  // ---------------- right column
  const x = 1100, w = 156;
  const r0 = panel(c, x, 74, w, 150, { title: 'POWER', jp: '電源', color: RD(), fill: 'rgba(110,0,0,0.8)' });
  sevenSeg(c, '00:00:00', r0.x, r0.y + 2, 20, RD(), RD(0.1));
  const row = (k, v, y, col = RD()) => { text(c, k, r0.x, y, { size: 8.5, color: col, track: 1 }); text(c, v, r0.x + r0.w, y, { weight: 700, size: 9, color: col, align: 'right' }); };
  row('INTERNAL', '0 %', r0.y + 40); segMeter(c, r0.x, r0.y + 45, r0.w, 6, 12, 0, { dim: RD(0.2) });
  row('EXTERNAL', 'CUT', r0.y + 66);
  c.font = jp(10.5, 700, false); c.fillStyle = RD(); c.fillText('内部電源 0  外部電源 切断', r0.x, r0.y + 84);
  text(c, 'STILL MOVING', r0.x, r0.y + 100, { weight: 700, size: 9.5, color: LI(), track: 1.5 });
  const r1 = panel(c, x, 234, w, 190, { title: 'SIGNAL', jp: '信号', color: P() });
  for (let i = 0; i < 11; i++) {
    const err = hash(i, 77) < 0.22;
    text(c, err ? `${hexData(i, 1, 4)} ERR ${hexData(i, 2, 4)}` : `${hexData(i, 1, 4)} ${hexData(i, 3, 8)}`, r1.x, r1.y + 10 + i * 14.5, { size: 9, color: err ? RD() : LI(0.9 - i * 0.05), track: 0.8 });
  }
  const r2 = panel(c, x, 434, w, 170, { title: 'PILOT 01', color: LI() });
  const prow = (k, v, y) => { text(c, k, r2.x, y, { size: 8.5, color: RD(0.8), track: 1 }); text(c, v, r2.x + r2.w, y, { weight: 700, size: 9, color: RD(), align: 'right' }); };
  prow('RESPONSE', 'NONE', r2.y + 10); prow('NEURAL', 'REVERSE', r2.y + 28); prow('EGO BORDER', 'LOST', r2.y + 46);
  c.font = jp(10.5, 700, false); c.fillStyle = RD(); c.fillText('応答なし  神経接続逆流', r2.x, r2.y + 66);
  c.fillStyle = RD(); chamferPath(c, r2.x, r2.y + 80, r2.w, 30, 7); c.fill();
  text(c, 'WARNING', r2.x + r2.w / 2, r2.y + 100, { weight: 700, size: 12, color: rgba('ink'), align: 'center', track: 3 });

  // ---------------- ECG
  const e = panel(c, 40, 664, 700, 108, { title: 'ECG', jp: '心電図', color: LI() });
  const gw = e.w - 130;
  c.strokeStyle = LI(0.1); c.lineWidth = 0.6; c.beginPath();
  for (let i = 0; i <= 24; i++) { const xx = e.x + (gw * i) / 24; c.moveTo(xx, e.y); c.lineTo(xx, e.y + e.h); }
  for (let j = 0; j <= 4; j++) { const yy = e.y + (e.h * j) / 4; c.moveTo(e.x, yy); c.lineTo(e.x + gw, yy); } c.stroke();
  const qrs = (dt) => 0.12 * Math.exp(-(((dt + 0.09) / 0.025) ** 2)) - 0.18 * Math.exp(-(((dt + 0.018) / 0.008) ** 2)) + Math.exp(-((dt / 0.009) ** 2)) - 0.35 * Math.exp(-(((dt - 0.022) / 0.01) ** 2)) + 0.2 * Math.exp(-(((dt - 0.17) / 0.04) ** 2));
  const kicks = []; for (let k = 0.15; k < 3.6; k += 0.45 * (hash(k * 10, 1) < 0.3 ? 0.5 : 1)) kicks.push([k, 0.7 + 0.3 * hash(k * 10, 2)]);
  c.save(); c.beginPath(); let hx = 0, hy = 0;
  for (let i = 0; i <= 700; i++) {
    const ts = (3.6 * i) / 700; let v = 0;
    for (const [kt, s] of kicks) { const dt = ts - kt; if (dt > -0.15 && dt < 0.3) v += qrs(dt) * s; }
    v += (fbm(ts * 40, 3) - 0.5) * 0.08;
    const xx = e.x + (gw * i) / 700, yy = e.y + e.h * 0.64 - v * e.h * 0.56;
    if (i) c.lineTo(xx, yy); else c.moveTo(xx, yy); hx = xx; hy = yy;
  }
  c.strokeStyle = LI(); c.lineWidth = 1.5; c.lineJoin = 'round'; c.shadowColor = LI(); c.shadowBlur = 8; c.stroke(); c.restore();
  c.fillStyle = rgba('bone'); c.beginPath(); c.arc(hx, hy, 2.5, 0, TAU); c.fill();
  const rx = e.x + e.w - 118;
  c.fillStyle = LI(0.5); c.fillRect(rx - 8, e.y, 1, e.h);
  text(c, 'HEART RATE', rx, e.y + 8, { weight: 600, size: 9, color: LI(), track: 1.5 });
  sevenSeg(c, '266', rx, e.y + 16, 38, LI(), LI(0.07), { glow: 8 });
  c.font = jp(11, 700, false); c.fillStyle = LI(); c.fillText('心拍数  BPM', rx, e.y + 72);
  c.fillStyle = RD(); c.beginPath(); c.arc(rx + 104, e.y + 6, 4.5, 0, TAU); c.fill();

  // ---------------- limiter
  const l = panel(c, 756, 664, 500, 108, { title: 'LIMITER', jp: 'リミッター全解除', color: P() });
  const n = 24, lbw = (l.w - (n - 1) * 4) / n;
  for (let i = 0; i < n; i++) {
    const v = 0.86 + 0.14 * hash(i, 44);
    segMeter(c, l.x + i * (lbw + 4), l.y + 2, lbw, l.h - 16, 10, v, { vertical: true, color: P(), hot: RD(), hotFrom: 0.5, dim: P(0.12), gap: 1.5 });
  }
  for (let i = 0; i < n; i += 4) text(c, 'OVR', l.x + i * (lbw + 4), l.y + l.h + 1, { weight: 700, size: 8, color: RD(), track: 1 });

  // ---------------- frame + clap flare
  c.strokeStyle = P(0.55); c.lineWidth = 0.8; c.strokeRect(20, 64, W - 40, 716);
  brackets(c, 20, 64, W - 40, 716, 22, P(), 2.2);
  c.strokeStyle = RD(0.85); c.lineWidth = 3; c.strokeRect(24, 68, W - 48, 708);

  return {
    glitches: [
      { y: 186, h: 4, dx: 22, split: 4 }, { y: 268, h: 10, dx: -34, split: 6 }, { y: 392, h: 3, dx: 16, split: 3 },
      { y: 452, h: 6, dx: 26, split: 5 }, { y: 556, h: 2, dx: -10, split: 2 }, { y: 716, h: 3, dx: 12, split: 3 },
    ], ca: 1.3, threshold: 0.55, bloom: 1,
  };
});
