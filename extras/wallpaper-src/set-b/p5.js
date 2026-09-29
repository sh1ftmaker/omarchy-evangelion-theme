// 5 — PATTERN BLUE: frozen frame of the alert plate (drop 1b, a clap just landed).
boot((c, W, H) => {
  const R = rng(505);
  // ---------------- background: the EMERGENCY tile wall (columns = mel bands from the centre out)
  const words = ['EMERGENCY', 'WARNING', 'DANGER', '警告', '緊急', 'ALERT'];
  const tw = 64, th = 22, cols = Math.ceil(W / tw) + 1, rows = Math.ceil(H / th) + 1;
  const spec = (k) => clamp(0.95 * Math.exp(-k * 2.2) + 0.25 * fbm(k * 6, 3) - 0.08); // mel level, bass in the middle
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const x = i * tw - 20, y = j * th + 2;
    const cx = x + tw / 2 - W / 2, cy = y - H / 2;
    const k = Math.abs(cx) / (W / 2);
    const lev = spec(k + Math.abs(cy) / H * 0.25);
    const lit = hash(i, j, 1) < lev * 0.9;
    const ring = Math.abs(Math.hypot(cx, cy * 1.6) - 520) < 22; // the clap ring of inverted tiles
    const w = words[Math.floor(hash(i, j, 2) * words.length)];
    c.save();
    c.beginPath(); c.rect(x + 1, y + 1, tw - 2, th - 2);
    if (ring && hash(i, j, 5) < 0.8) {
      c.fillStyle = rgba('red', 0.55); c.fill();
      c.fillStyle = rgba('ink', 0.9);
    } else {
      c.strokeStyle = rgba('red', lit ? 0.3 : 0.08); c.lineWidth = 0.6; c.stroke();
      c.fillStyle = rgba('red', lit ? 0.28 + 0.2 * hash(i, j, 3) : 0.07);
    }
    c.font = /[　-鿿]/.test(w) ? jp(10, 700, false) : mono(700, 7.5);
    c.letterSpacing = '1px'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText(w, x + tw / 2, y + th / 2 + 0.5);
    c.restore();
  }
  // siren beam: a hard wedge of red light from the centre
  c.save();
  c.globalCompositeOperation = 'lighter';
  c.fillStyle = rgba('red', 0.07);
  c.beginPath(); c.moveTo(640, 360); c.arc(640, 360, 1400, -0.62, -0.38); c.closePath(); c.fill();
  c.beginPath(); c.moveTo(640, 360); c.arc(640, 360, 1400, Math.PI - 0.62, Math.PI - 0.38); c.closePath(); c.fill();
  c.restore();
  // darken the working area so the HUD reads
  c.fillStyle = 'rgba(5,4,3,0.55)'; c.fillRect(24, 64, W - 48, H - 128);

  // ---------------- top + bottom hazard bands and tickers
  hazard(c, 0, 0, W, 30, 6, rgba('red'), rgba('blood', 0.9), 20);
  c.fillStyle = rgba('ink'); c.fillRect(0, 30, W, 30);
  c.fillStyle = rgba('red'); c.fillRect(0, 30, W, 1.5); c.fillRect(0, 58.5, W, 1.5);
  c.fillStyle = rgba('red'); chamferPath(c, 0, 33, 214, 24, [0, 12, 0, 0]); c.fill();
  text(c, 'EMERGENCY', 10, 50, { weight: 700, size: 13, color: rgba('ink'), track: 3 });
  c.font = jp(14, 900, false); c.fillStyle = rgba('ink'); c.fillText('緊急事態', 140, 50);
  ticker(c, 226, 50, 1040, 'PATTERN BLUE CONFIRMED // パターン青 // ANGEL APPROACHING TOKYO-3 // 使徒接近 // ALL PERSONNEL TO FIRST-CLASS BATTLE STATIONS // 第一種戦闘配置 // EVACUATION ORDER ISSUED // 避難命令 //', 310, { size: 11, weight: 600, color: rgba('red', 0.95) });
  hazard(c, 0, 772, W, 28, -8, rgba('red'), rgba('blood', 0.9), 20);
  c.fillStyle = rgba('ink'); c.fillRect(0, 744, W, 28);
  c.fillStyle = rgba('red'); c.fillRect(0, 744, W, 1.5); c.fillRect(0, 770.5, W, 1.5);
  ticker(c, 10, 763, W - 20, 'CODE 601 // 解析不能 // BLOOD TYPE: BLUE // A.T. FIELD DETECTED // 位相空間 確認 // MAGI: 承認 2  否決 1 // INTERCEPT SYSTEMS 0% READY // 迎撃システム // ', 120, { size: 10.5, weight: 600, color: rgba('orange', 0.9) });

  // ---------------- left: 3x5 alert panel grid
  const gx = 36, gy = 76, cw = 92, chh = 58, gp = 6;
  c.save(); evaLabel(c, gx, gy + 4, 'sector alert matrix', '警戒区域 状況', { color: rgba('orange') }); c.restore();
  const secs = ['A-01', 'A-02', 'A-03', 'B-11', 'B-12', 'B-13', 'C-07', 'C-08', 'C-09', 'D-20', 'D-21', 'D-22', 'GEO-1', 'GEO-2', 'GEO-3'];
  const hot = new Set([1, 3, 4, 7, 9, 10, 12]);
  const jpS = ['第3新東京市', '強羅防衛線', '芦ノ湖', '二子山', '駒ヶ岳', 'ジオフロント'];
  for (let i = 0; i < 15; i++) {
    const x = gx + (i % 3) * (cw + gp), y = gy + 34 + Math.floor(i / 3) * (chh + gp);
    const on = hot.has(i), blue = i === 7;
    const col = blue ? rgba('cyan') : on ? rgba('red') : rgba('orange', 0.9);
    chamferPath(c, x, y, cw, chh, [0, 9, 0, 0]);
    c.fillStyle = on ? (blue ? rgba('cyan', 0.9) : rgba('red', 0.92)) : 'rgba(18,12,6,0.85)'; c.fill();
    c.strokeStyle = col; c.lineWidth = 1; c.stroke();
    const tc = on ? rgba('ink') : col;
    text(c, secs[i], x + 6, y + 13, { weight: 700, size: 9.5, color: tc, track: 1.5 });
    text(c, on ? (blue ? 'TARGET' : 'ALERT') : 'NORMAL', x + cw - 6, y + 13, { weight: 700, size: 8, color: tc, align: 'right' });
    c.font = jp(11, 700, false); c.fillStyle = tc; c.fillText(on ? (blue ? '目標捕捉' : '警報') : jpS[i % 6], x + 6, y + 31);
    segMeter(c, x + 6, y + 40, cw - 12, 7, 12, on ? 0.75 + 0.25 * hash(i, 4) : 0.15 + 0.4 * hash(i, 5), on ? { color: rgba('ink'), hot: rgba('ink'), dim: 'rgba(0,0,0,0.25)' } : { dim: rgba('orange', 0.12) });
    text(c, hexData(i, 3, 6), x + 6, y + 55, { size: 6.5, color: on ? 'rgba(0,0,0,0.7)' : rgba('orange', 0.5), track: 1 });
  }
  // emergency log
  const lg = panel(c, 36, 470, 288, 262, { title: 'emergency log', jp: '緊急記録', color: rgba('red') });
  const logs = [
    ['15:42:07', 'ANGEL SIGNAL CONFIRMED', 'red'], ['15:42:07', 'PATTERN BLUE // パターン青', 'cyan'], ['15:42:08', 'LEVEL-1 ALERT ISSUED', 'red'],
    ['15:42:09', 'MAGI DELIBERATION 承認', 'green'], ['15:42:10', 'TOKYO-3 BATTLE MODE', 'orange'], ['15:42:11', 'CITY BLOCKS RETRACTING', 'orange'],
    ['15:42:12', 'A.T. FIELD 展開 確認', 'amber'], ['15:42:12', 'N2 MINE: NO EFFECT', 'red'], ['15:42:13', 'UNIT-01 LAUNCH PREP', 'orange'],
    ['15:42:14', 'CODE 601 解析不能', 'cyan'], ['15:42:15', 'INTERCEPT 0% READY', 'red'], ['15:42:15', 'EVACUATION 71%', 'amber'],
  ];
  logs.forEach(([t, s, k], i) => {
    const y = lg.y + 12 + i * 18.5;
    const inv = i === 7;
    if (inv) { c.fillStyle = rgba('red'); c.fillRect(lg.x - 2, y - 11, lg.w + 4, 15); }
    text(c, t, lg.x, y, { size: 9, color: inv ? rgba('ink') : rgba('orange', 0.55), track: 0.5 });
    c.font = mono(600, 9.5); c.letterSpacing = '1px';
    const en = s.replace(/[　-鿿゠-ヿ]+/g, (m) => m);
    c.fillStyle = inv ? rgba('ink') : rgba(k); c.fillText(en, lg.x + 58, y); c.letterSpacing = '0px';
  });
  c.fillStyle = rgba('red'); c.fillRect(lg.x, lg.y + 12 + 12 * 18.5 - 8, 7, 11);

  // ---------------- centre: EMERGENCY box (inverted on the clap)
  const bx = 350, by = 100, bw = 580, bh = 272;
  // outer glow frame
  c.save(); c.shadowColor = rgba('red'); c.shadowBlur = 30;
  chamferPath(c, bx, by, bw, bh, 14); c.fillStyle = rgba('red'); c.fill(); c.restore();
  warningBox(c, bx, by, bw, bh, 'EMERGENCY', '緊 急 事 態', { fill: rgba('red'), color: rgba('ink'), wcol: rgba('ink'), phase: 10, ws: 0.5, wy: 0.66 });
  c.save(); c.strokeStyle = rgba('red'); c.lineWidth = 1; chamferPath(c, bx - 7, by - 7, bw + 14, bh + 14, 18); c.stroke(); c.restore();
  brackets(c, bx - 16, by - 16, bw + 32, bh + 32, 22, rgba('amber'), 2);
  text(c, 'LEVEL 1 // CODE 601', bx - 12, by - 22, { weight: 700, size: 10, color: rgba('amber'), track: 2.5 });
  text(c, 'ALARM 00:00:07:44', bx + bw + 12, by - 22, { weight: 700, size: 10, color: rgba('amber'), track: 2.5, align: 'right' });

  // PATTERN BLUE card
  const py = 400;
  condensed(c, 'PATTERN', bx - 4, py + 92, 118, { sx: 0.56, color: rgba('cyan'), glow: 18 });
  const pw = condensed(c, 'PATTERN', bx - 4, py + 92, 118, { sx: 0.56, color: rgba('cyan') });
  condensed(c, 'BLUE', bx + pw + 14, py + 92, 118, { sx: 0.56, color: rgba('cyan'), glow: 18 });
  const bw2 = condensed(c, 'BLUE', bx + pw + 14, py + 92, 118, { sx: 0.56, color: rgba('cyan') });
  const cardEnd = bx + pw + 14 + bw2;
  c.fillStyle = rgba('cyan'); c.fillRect(bx, py + 104, cardEnd - bx, 2.5);
  c.font = jp(22, 900, true); c.fillStyle = rgba('cyan'); c.fillText('パターン青', bx, py + 134);
  text(c, 'ANGEL IDENTIFIED // WAVEFORM MATCH 99.89%', bx + 132, py + 130, { weight: 600, size: 9.5, color: rgba('cyan', 0.85), track: 1.6 });
  // intercept countdown
  const cx0 = cardEnd + 24;
  evaLabel(c, cx0, py + 20, 'contact in', '接触まで', { color: rgba('amber'), size: 0.85 });
  sevenSeg(c, '02:14', cx0, py + 44, 40, rgba('amber'), rgba('amber', 0.08), { glow: 8 });
  segMeter(c, cx0, py + 94, 930 - cx0, 6, 18, 0.62, { color: rgba('amber'), hotFrom: 0.5 });

  // siren scope + spectrum strip
  const sp = panel(c, 350, 552, 580, 180, { title: 'siren scope', jp: '警報波形', color: rgba('red') });
  c.save();
  c.strokeStyle = rgba('red', 0.12); c.lineWidth = 0.6;
  for (let i = 0; i <= 16; i++) { const x = sp.x + (sp.w * i) / 16; c.beginPath(); c.moveTo(x, sp.y); c.lineTo(x, sp.y + 78); c.stroke(); }
  for (let j = 0; j <= 4; j++) { const y = sp.y + (78 * j) / 4; c.beginPath(); c.moveTo(sp.x, y); c.lineTo(sp.x + sp.w, y); c.stroke(); }
  c.beginPath();
  for (let i = 0; i <= 600; i++) {
    const u = i / 600, env = 0.35 + 0.65 * Math.abs(Math.sin(u * TAU * 1.5));
    const v = Math.sin(u * 220 + 6 * Math.sin(u * 9)) * env * 0.7 + (fbm(u * 60, 9) - 0.5) * 0.5;
    const x = sp.x + u * sp.w, y = sp.y + 39 - v * 34;
    if (i) c.lineTo(x, y); else c.moveTo(x, y);
  }
  c.strokeStyle = rgba('red'); c.lineWidth = 1.2; c.shadowColor = rgba('red'); c.shadowBlur = 6; c.stroke();
  c.restore();
  // spectrum: 48 bars
  const n = 48, sw = (sp.w - (n - 1) * 2) / n;
  for (let i = 0; i < n; i++) {
    const v = clamp(0.95 * Math.exp(-i / 14) + 0.3 * fbm(i * 0.4, 11) - 0.05);
    segMeter(c, sp.x + i * (sw + 2), sp.y + 88, sw, sp.h - 94, 12, v, { vertical: true, hotFrom: 0.7, gap: 1.2 });
  }

  // ---------------- right: the Angel analysis
  const ax = 956, aw = 288;
  const ap = panel(c, ax, 76, aw, 400, { title: 'angel analysis', jp: '使徒 解析', color: rgba('cyan') });
  // crystal octahedron wireframe
  const ocx = ap.x + ap.w / 2, ocy = ap.y + 136, s = 88;
  c.save();
  c.strokeStyle = rgba('cyan', 0.25); c.lineWidth = 0.7;
  for (const r of [40, 80, 120]) { c.beginPath(); c.arc(ocx, ocy, r, 0, TAU); c.stroke(); }
  c.beginPath(); c.moveTo(ocx - 130, ocy); c.lineTo(ocx + 130, ocy); c.moveTo(ocx, ocy - 130); c.lineTo(ocx, ocy + 130); c.stroke();
  const rot = 0.55, tilt = 0.35;
  const V = [[0, -1.35, 0], [0, 1.35, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1]].map(([x, y, z]) => {
    const x1 = x * Math.cos(rot) - z * Math.sin(rot), z1 = x * Math.sin(rot) + z * Math.cos(rot);
    const y1 = y * Math.cos(tilt) - z1 * Math.sin(tilt), z2 = y * Math.sin(tilt) + z1 * Math.cos(tilt);
    return [ocx + x1 * s, ocy + y1 * s, z2];
  });
  const F = [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 2, 4], [1, 4, 3], [1, 3, 5], [1, 5, 2]];
  F.forEach((f, i) => {
    c.beginPath(); f.forEach((k, j) => j ? c.lineTo(V[k][0], V[k][1]) : c.moveTo(V[k][0], V[k][1])); c.closePath();
    c.fillStyle = rgba('cyan', 0.06 + 0.12 * hash(i, 8)); c.fill();
  });
  c.strokeStyle = rgba('cyan'); c.lineWidth = 1.4; c.shadowColor = rgba('cyan'); c.shadowBlur = 10;
  F.forEach((f) => { c.beginPath(); f.forEach((k, j) => j ? c.lineTo(V[k][0], V[k][1]) : c.moveTo(V[k][0], V[k][1])); c.closePath(); c.stroke(); });
  c.shadowBlur = 0;
  // core
  c.fillStyle = rgba('red'); c.beginPath(); c.arc(ocx, ocy + 6, 7, 0, TAU); c.fill();
  c.restore();
  brackets(c, ocx - 60, ocy - 70, 120, 140, 12, rgba('cyan'), 1.5);
  text(c, 'LOCK', ocx + 64, ocy - 60, { weight: 700, size: 9, color: rgba('cyan'), track: 2 });
  text(c, 'Z-AXIS 0.35', ap.x, ap.y + 12, { size: 8.5, color: rgba('cyan', 0.7) });
  text(c, 'ROT 031.5°', ap.x + ap.w, ap.y + 12, { size: 8.5, color: rgba('cyan', 0.7), align: 'right' });
  // BLOOD TYPE: BLUE block
  const by2 = ap.y + 254;
  c.fillStyle = rgba('cyan'); chamferPath(c, ap.x, by2, ap.w, 34, [0, 10, 0, 10]); c.fill();
  text(c, 'BLOOD TYPE: BLUE', ap.x + ap.w / 2, by2 + 23, { weight: 700, size: 16, color: rgba('ink'), track: 3, align: 'center' });
  const arows = [['WAVEFORM', 'PATTERN BLUE'], ['CLASS', '第5使徒'], ['A.T. FIELD', '展開中 / DEPLOYED'], ['STATUS', '解析中']];
  arows.forEach(([k, v], i) => {
    const y = by2 + 50 + i * 16;
    text(c, k, ap.x, y, { size: 9, color: rgba('cyan', 0.7) });
    c.font = /[　-鿿]/.test(v) ? jp(11, 700, false) : mono(700, 9.5); c.fillStyle = i === 3 ? rgba('red') : rgba('cyan'); c.textAlign = 'right';
    c.fillText(v, ap.x + ap.w, y); c.textAlign = 'left';
  });
  // 解析中 big blinking tab
  c.fillStyle = rgba('red'); chamferPath(c, ap.x + ap.w - 84, ap.y - 24 + 0, 84, 16, [0, 0, 0, 0]);
  // approach panel
  const rp = panel(c, ax, 490, aw, 242, { title: 'approach', jp: '使徒接近', color: rgba('orange') });
  text(c, 'RANGE', rp.x, rp.y + 12, { size: 9, color: rgba('orange', 0.7) });
  sevenSeg(c, '12.84', rp.x, rp.y + 20, 42, rgba('orange'), rgba('orange', 0.07), { glow: 6 });
  text(c, 'KM', rp.x + 150, rp.y + 60, { weight: 700, size: 11, color: rgba('orange') });
  c.font = jp(22, 900, false); c.fillStyle = rgba('red'); c.textAlign = 'right'; c.fillText('解析中', rp.x + rp.w, rp.y + 40); c.textAlign = 'left';
  text(c, 'ANALYSING', rp.x + rp.w, rp.y + 58, { weight: 700, size: 9, color: rgba('red'), align: 'right', track: 2 });
  scale(c, rp.x, rp.y + 92, rp.x + rp.w, rp.y + 92, 40, { major: 10, color: rgba('orange', 0.8), side: -1, label: (i) => String(40 - i) });
  // contact marker on the scale
  const mx = rp.x + rp.w * (1 - 12.84 / 40);
  c.fillStyle = rgba('cyan'); c.beginPath(); c.moveTo(mx, rp.y + 88); c.lineTo(mx - 5, rp.y + 80); c.lineTo(mx + 5, rp.y + 80); c.closePath(); c.fill();
  const sens = [['SEISMIC', 0.82], ['THERMAL', 0.64], ['EM FIELD', 0.93], ['A.T. PHASE', 0.71], ['GAMMA', 0.38]];
  sens.forEach(([k, v], i) => {
    const y = rp.y + 118 + i * 16;
    text(c, k, rp.x, y + 7, { size: 8.5, color: rgba('orange', 0.75) });
    segMeter(c, rp.x + 74, y, rp.w - 110, 8, 20, v, { hotFrom: 0.75 });
    text(c, String(Math.round(v * 100)).padStart(3, '0'), rp.x + rp.w, y + 7, { weight: 700, size: 8.5, color: v > 0.75 ? rgba('red') : rgba('orange'), align: 'right' });
  });

  // ---------------- frame ticks + corner brackets
  brackets(c, 12, 68, W - 24, 668, 26, rgba('red', 0.9), 2);
  for (let y = 80; y < 730; y += 10) { c.fillStyle = rgba('red', y % 50 === 0 ? 0.8 : 0.35); c.fillRect(14, y, y % 50 === 0 ? 10 : 5, 1); c.fillRect(W - 14 - (y % 50 === 0 ? 10 : 5), y, y % 50 === 0 ? 10 : 5, 1); }

  return { glitches: [{ y: 210, h: 5, dx: 14, split: 3 }, { y: 318, h: 3, dx: -9, split: 2 }, { y: 612, h: 7, dx: 20, split: 4 }], threshold: 0.62, bloom: 0.8 };
});
