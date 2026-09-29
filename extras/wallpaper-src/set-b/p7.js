// 7 — INTERNAL BATTERY: the activity-limit countdown, frozen at one minute left.
boot((c, W, H) => {
  const AMB = mix('amber', 'orange', 0.3), OR = rgba('orange');
  // ---------------- background: faint hex field + scan rules
  hexGrid(-20, 20, W + 40, H, 16, (x, y, col, row) => {
    const d = Math.hypot(x - 640, (y - 330) * 1.5);
    const a = 0.03 + 0.06 * Math.max(0, 1 - d / 700) + (hash(col, row, 3) < 0.03 ? 0.12 : 0);
    hexPath(c, x, y, 14.5); c.strokeStyle = rgba('orange', a); c.lineWidth = 0.6; c.stroke();
  });
  c.fillStyle = 'rgba(5,4,3,0.45)'; c.fillRect(0, 0, W, H);

  // ---------------- chrome: top band + ticker, bottom hazard
  hazard(c, 0, 0, W, 30, 0, rgba('amber', 0.9), rgba('ink'), 16);
  c.fillStyle = rgba('ink'); c.fillRect(0, 30, W, 26);
  c.fillStyle = OR; c.fillRect(0, 30, W, 1.2); c.fillRect(0, 55, W, 1.2);
  c.fillStyle = OR; chamferPath(c, 0, 32, 250, 22, [0, 11, 0, 0]); c.fill();
  text(c, 'INTERNAL BATTERY', 10, 48, { weight: 700, size: 12, color: rgba('ink'), track: 2.5 });
  c.font = jp(12, 900, false); c.fillStyle = rgba('ink'); c.fillText('内部電源', 186, 48);
  ticker(c, 262, 48, W - 270, 'UMBILICAL CABLE PURGED // アンビリカルケーブル 切断 // SWITCHING TO INTERNAL POWER // 内部電源に切り替え // ACTIVITY LIMIT IMMINENT // 活動限界まで // EVA UNIT-01 // S² ENGINE NOT INSTALLED //', 40, { size: 10.5, weight: 600, color: rgba('orange', 0.95) });
  hazard(c, 0, 776, W, 24, 9, rgba('amber', 0.9), rgba('ink'), 16);

  // ---------------- title row
  const tx = 60;
  condensed(c, 'ACTIVITY', tx - 4, 150, 98, { sx: 0.56, color: rgba('bone') });
  const lw = condensed(c, 'ACTIVITY', tx - 4, 150, 98, { sx: 0.56, color: rgba('bone'), bold: 0 });
  condensed(c, 'LIMIT', tx + lw + 10, 150, 98, { sx: 0.56, color: OR });
  c.font = jp(58, 900, true); c.fillStyle = rgba('bone'); c.textAlign = 'right';
  c.fillText('活動限界まで', 1222, 146); c.textAlign = 'left';
  text(c, 'TIME REMAINING UNTIL ACTIVITY LIMIT // UNIT-01 // INTERNAL POWER ONLY', 1222, 168, { weight: 600, size: 9.5, color: rgba('orange', 0.8), align: 'right', track: 1.8 });
  c.fillStyle = OR; c.fillRect(tx, 162, 520, 2.5);
  text(c, 'EVA-01 // TEST TYPE', tx, 180, { weight: 600, size: 9.5, color: rgba('orange', 0.8), track: 2 });

  // ---------------- the timer
  const fx = 44, fy = 196, fw = W - 88, fh = 262;
  chamferPath(c, fx, fy, fw, fh, 22); c.fillStyle = 'rgba(14,8,2,0.9)'; c.fill();
  c.strokeStyle = OR; c.lineWidth = 2; c.stroke();
  chamferPath(c, fx + 7, fy + 7, fw - 14, fh - 14, 17); c.strokeStyle = rgba('orange', 0.35); c.lineWidth = 0.8; c.stroke();
  // hazard wedges on the frame corners
  hazard(c, fx + 26, fy + 7, 150, 12, 3, rgba('red'), null, 10);
  hazard(c, fx + fw - 176, fy + fh - 19, 150, 12, 3, rgba('red'), null, 10);
  // labels above each group
  const dh = 150, dy = fy + 56;
  const groups = [['HOUR', '時'], ['MIN', '分'], ['SEC', '秒'], ['1/100', '']];
  // measure: draw digits
  const digits = '00:00:59:87';
  const dw = sevenSeg(c, digits, 0, -9999, dh, 'rgba(0,0,0,0)', null);
  const x0 = (W - dw) / 2 - 8;
  // lit digits: hot amber, the seconds in red (one minute left)
  sevenSeg(c, '88:88:88:88', x0, dy, dh, rgba('amber', 0.07), null);
  sevenSeg(c, digits, x0, dy, dh, AMB, null, { glow: 12 });
  // re-draw seconds group in red-amber
  const gW = sevenSeg(c, '00', 0, -9999, dh, 'rgba(0,0,0,0)', null), wc = sevenSeg(c, ':', 0, -9999, dh, 'rgba(0,0,0,0)', null);
  const gx = (i) => x0 + i * (gW + wc);
  groups.forEach(([en, j], i) => {
    const x = gx(i) + 6;
    text(c, en, x, dy - 12, { weight: 700, size: 10, color: rgba('orange', 0.85), track: 2.5 });
    if (j) { c.font = jp(11, 700, false); c.fillStyle = rgba('orange', 0.85); c.fillText(j, x + 58, dy - 12); }
  });
  sevenSeg(c, '87', gx(3), dy, dh, rgba('red'), null, { glow: 14 });
  // lock-on bracket over the seconds (a vocal chop warning)
  brackets(c, gx(2) - 14, dy - 8, gW + 20, dh + 16, 16, rgba('cyan'), 2);
  text(c, 'ANGEL SIGNAL // 使徒反応', gx(2) - 14, dy + dh + 24, { weight: 700, size: 9, color: rgba('cyan'), track: 1.5, font: jp(10, 700, false) });
  // drain meter under the digits
  segMeter(c, fx + 26, fy + fh - 36, fw - 420, 12, 60, 0.2, { color: AMB, hot: rgba('red'), hotFrom: 0, dim: rgba('orange', 0.1), gap: 2 });
  segMeter(c, fx + 26, fy + fh - 36, fw - 420, 12, 60, 0.2, { color: rgba('red'), hotFrom: 1, dim: 'rgba(0,0,0,0)', gap: 2 });
  text(c, 'CHARGE 20.0%  //  残量', fx + 190, fy + 19, { weight: 700, size: 11, color: rgba('red'), track: 2, font: mono(700, 11) });
  // mode strip
  const modes = [['STOP', '停止'], ['SLOW', '低速'], ['NORMAL', '通常'], ['RACING', '全開']];
  modes.forEach(([en, j], i) => {
    const x = fx + fw - 372 + i * 84, y = fy + fh - 40, on = i === 3;
    chamferPath(c, x, y, 78, 20, [0, 6, 0, 6]);
    c.fillStyle = on ? rgba('red') : 'rgba(0,0,0,0)'; c.fill(); c.strokeStyle = on ? rgba('red') : rgba('orange', 0.5); c.lineWidth = 0.8; c.stroke();
    text(c, en, x + 6, y + 14, { weight: 700, size: 8.5, color: on ? rgba('ink') : rgba('orange', 0.6), track: 1.2 });
    c.font = jp(9, 700, false); c.fillStyle = on ? rgba('ink') : rgba('orange', 0.6); c.textAlign = 'right'; c.fillText(j, x + 72, y + 14); c.textAlign = 'left';
  });

  // ---------------- bottom-left: power source schematic
  const ps = panel(c, 44, 478, 380, 286, { title: 'power source', jp: '電源系統', color: OR });
  // EXTERNAL box (cut)
  const ex = ps.x + 4, ey = ps.y + 8;
  chamferPath(c, ex, ey, 160, 72, [0, 10, 0, 10]); c.fillStyle = rgba('blood', 0.8); c.fill(); c.strokeStyle = rgba('red'); c.lineWidth = 1.5; c.stroke();
  text(c, 'EXTERNAL', ex + 10, ey + 20, { weight: 700, size: 11, color: rgba('red'), track: 2 });
  c.font = jp(19, 900, false); c.fillStyle = rgba('red'); c.fillText('外部電源', ex + 10, ey + 48);
  c.fillStyle = rgba('red'); chamferPath(c, ex + 10, ey + 57, 140, 1, 0);
  text(c, 'DISCONNECTED', ex + 10, ey + 66, { weight: 700, size: 8, color: rgba('red', 0.8), track: 1.5 });
  // CUT stamp
  c.save(); c.translate(ex + 126, ey + 40); c.rotate(-0.18);
  c.strokeStyle = rgba('red'); c.lineWidth = 2; c.strokeRect(-25, -15, 50, 30);
  c.font = jp(17, 900, false); c.fillStyle = rgba('red'); c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText('切断', 0, 0);
  c.restore();
  // INTERNAL box (active)
  const ix = ps.x + ps.w - 164, iy = ey;
  chamferPath(c, ix, iy, 160, 72, [0, 10, 0, 10]); c.fillStyle = rgba('amber'); c.fill();
  text(c, 'INTERNAL', ix + 10, iy + 20, { weight: 700, size: 11, color: rgba('ink'), track: 2 });
  c.font = jp(22, 900, false); c.fillStyle = rgba('ink'); c.fillText('内部電源', ix + 10, iy + 50);
  text(c, 'ACTIVE // 作動中', ix + 10, iy + 66, { weight: 700, size: 8, color: rgba('ink'), font: jp(9, 700, false) });
  // umbilical: cable with a break
  const cy = ey + 120;
  c.strokeStyle = rgba('red'); c.lineWidth = 3; c.setLineDash([]);
  c.beginPath(); c.moveTo(ex + 80, ey + 72); c.lineTo(ex + 80, cy); c.lineTo(ex + 150, cy); c.stroke();
  c.beginPath(); c.moveTo(ex + 176, cy + 6); c.lineTo(ex + 200, cy - 6); c.stroke();
  c.strokeStyle = AMB; c.beginPath(); c.moveTo(ix + 80, iy + 72); c.lineTo(ix + 80, cy); c.lineTo(ex + 222, cy); c.stroke();
  // sparks at the break
  for (let k = 0; k < 9; k++) { const a = hash(k, 2) * TAU, r = 6 + hash(k, 3) * 12; c.strokeStyle = rgba('amber', 0.9); c.lineWidth = 1; c.beginPath(); c.moveTo(ex + 188, cy); c.lineTo(ex + 188 + Math.cos(a) * r, cy + Math.sin(a) * r); c.stroke(); }
  text(c, 'UMBILICAL CABLE // アンビリカルケーブル', ps.x + 4, cy + 30, { weight: 600, size: 9, color: rgba('orange', 0.8), font: jp(10, 600, false) });
  // readouts
  const rows = [['VOLTAGE', '380 V', 'orange'], ['DRAW', '112.4 MW', 'amber'], ['S² ENGINE', 'NONE', 'red'], ['RESERVE', 'STANDBY', 'orange']];
  rows.forEach(([k, v, col], i) => {
    const y = cy + 54 + i * 17;
    text(c, k, ps.x + 4, y, { size: 9.5, color: rgba('orange', 0.7) });
    c.fillStyle = rgba('orange', 0.2); c.fillRect(ps.x + 90, y - 3, ps.w - 190, 1);
    text(c, v, ps.x + ps.w - 4, y, { weight: 700, size: 10, color: rgba(col), align: 'right' });
  });

  // ---------------- bottom-centre: battery cells
  const bp = panel(c, 440, 478, 400, 286, { title: 'battery cells', jp: '電池残量', color: OR });
  const cells = [[0, 'A'], [0.0, 'B'], [0.6, 'C']];
  cells.forEach(([v, id], i) => {
    const x = bp.x + 10 + i * 128, y = bp.y + 26, w = 104, h = 170;
    const col = v > 0.3 ? AMB : rgba('red');
    c.fillStyle = v > 0 ? col : rgba('red', 0.5); c.fillRect(x + 36, y - 10, 32, 10);
    chamferPath(c, x, y, w, h, [0, 0, 8, 8]); c.strokeStyle = v > 0 ? col : rgba('red', 0.7); c.lineWidth = 2; c.stroke();
    segMeter(c, x + 8, y + 8, w - 16, h - 16, 10, v, { vertical: true, color: col, hot: col, hotFrom: 2, dim: rgba(v > 0 ? 'amber' : 'red', 0.08), gap: 4 });
    if (v === 0) {
      c.save(); c.strokeStyle = rgba('red', 0.8); c.lineWidth = 1.5; c.beginPath(); c.moveTo(x + 8, y + 8); c.lineTo(x + w - 8, y + h - 8); c.moveTo(x + w - 8, y + 8); c.lineTo(x + 8, y + h - 8); c.stroke(); c.restore();
      text(c, 'EMPTY', x + w / 2, y + h / 2 + 4, { weight: 700, size: 12, color: rgba('red'), align: 'center', track: 2 });
    }
    text(c, `CELL ${id}`, x, y + h + 20, { weight: 700, size: 10, color: v > 0 ? col : rgba('red'), track: 2 });
    text(c, v > 0 ? `${Math.round(v * 100)}%` : '0%', x + w, y + h + 20, { weight: 700, size: 10, color: v > 0 ? col : rgba('red'), align: 'right' });
  });
  text(c, 'TOTAL 20.0%  //  放電率 上昇  DRAIN RATE RISING', bp.x + 10, bp.y + bp.h - 6, { weight: 600, size: 9, color: rgba('red'), font: jp(10, 700, false) });

  // ---------------- bottom-right: discharge log + warnings
  const dp = panel(c, 856, 478, 380, 150, { title: 'discharge', jp: '放電曲線', color: OR });
  c.save();
  c.strokeStyle = rgba('orange', 0.1); c.lineWidth = 0.6;
  for (let i = 0; i <= 12; i++) { const x = dp.x + (dp.w * i) / 12; c.beginPath(); c.moveTo(x, dp.y); c.lineTo(x, dp.y + dp.h); c.stroke(); }
  for (let j = 0; j <= 4; j++) { const y = dp.y + (dp.h * j) / 4; c.beginPath(); c.moveTo(dp.x, y); c.lineTo(dp.x + dp.w, y); c.stroke(); }
  // rms envelope bars
  for (let i = 0; i < 90; i++) {
    const u = i / 90, v = (0.3 + 0.6 * u) * (0.5 + 0.5 * fbm(i * 0.35, 5)) * (i % 4 === 0 ? 1.3 : 1);
    c.fillStyle = rgba('orange', u < 0.8 ? 0.45 : 0.15); c.fillRect(dp.x + u * dp.w, dp.y + dp.h - v * dp.h * 0.5, dp.w / 90 - 1, v * dp.h * 0.5);
  }
  // discharge curve (steepening, kick bites)
  c.beginPath();
  for (let i = 0; i <= 200; i++) {
    const u = i / 200, p = Math.min(u, 0.8);
    let d = 0.72 * Math.pow(p / 1, 1.9) + 0.28 * (Math.floor(p * 48) / 48);
    const y = dp.y + d * dp.h * 1.1, x = dp.x + u * dp.w;
    if (i) c.lineTo(x, y); else c.moveTo(x, y);
  }
  c.strokeStyle = rgba('red'); c.lineWidth = 1.6; c.shadowColor = rgba('red'); c.shadowBlur = 6; c.stroke();
  c.restore();
  c.fillStyle = AMB; c.fillRect(dp.x + dp.w * 0.8, dp.y - 4, 1.2, dp.h + 8);
  text(c, 'NOW', dp.x + dp.w * 0.8 + 4, dp.y + 8, { weight: 700, size: 8, color: AMB });
  const wp = panel(c, 856, 640, 380, 124, { title: 'warning', jp: '警告', color: rgba('red') });
  const warn = [['外部電源 切断', 'EXTERNAL POWER CUT', 'red'], ['内部電源 作動', 'INTERNAL BATTERY ON', 'amber'], ['残り 1分', 'ONE MINUTE LEFT', 'red'], ['使徒 反応', 'ANGEL SIGNAL', 'cyan']];
  warn.forEach(([j, en, col], i) => {
    const y = wp.y + 12 + i * 20, inv = i === 2;
    if (inv) { c.fillStyle = rgba('red'); c.fillRect(wp.x - 2, y - 12, wp.w + 4, 17); }
    c.font = jp(11, 700, false); c.fillStyle = inv ? rgba('ink') : rgba(col); c.fillText(j, wp.x, y);
    text(c, en, wp.x + wp.w, y, { weight: 700, size: 9.5, color: inv ? rgba('ink') : rgba(col), align: 'right', track: 1.5 });
  });

  brackets(c, 16, 64, W - 32, 704, 24, rgba('orange', 0.8), 1.5);
  return { glitches: [{ y: 300, h: 4, dx: 10, split: 3 }, { y: 382, h: 2, dx: -6, split: 2 }], threshold: 0.6, bloom: 0.9 };
});
