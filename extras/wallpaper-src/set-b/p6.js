// 6 — SOUND ONLY: the council in the void (break 1 frozen frame; member 07 speaking).
boot((c, W, H) => {
  const SPEAK = 7;
  const chroma = [0.35, 0.18, 0.52, 0.22, 0.61, 0.3, 1.0, 0.27, 0.48, 0.2, 0.44, 0.15]; // pitch-class levels (C..B)
  const NOTES = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
  // camera at the centre of the ring, looking along +z, slight upward pitch
  const RING = 10, CZ = -6.5, f = 330, cx0 = W / 2, cy0 = 340, yaw = 0.0;
  const proj = ([x, y, z]) => {
    z -= CZ; const xr = x * Math.cos(yaw) - z * Math.sin(yaw), zr = x * Math.sin(yaw) + z * Math.cos(yaw);
    return [cx0 + (xr / zr) * f, cy0 - (y / zr) * f, zr];
  };
  const FLOOR = -6.2;
  // members: angle 0 = straight ahead; ids clockwise, member 07 ahead
  const mem = [];
  for (let i = 0; i < 12; i++) {
    const id = ((i + SPEAK - 1) % 12) + 1;
    let a = (i * TAU) / 12; if (a > Math.PI) a -= TAU;
    const h = 0.6 * Math.sin(i * 2.3 + 1) - 0.2; // floating height offset
    mem.push({ id, a, h, inten: chroma[id - 1], speak: id === SPEAK ? 1 : 0 });
  }
  const corners = (m, mirror, raw) => {
    const px = Math.sin(m.a) * RING, pz = Math.cos(m.a) * RING;
    const dl = Math.hypot(px, pz - CZ), tx = (pz - CZ) / dl, tz = -px / dl; // face turned to the camera
    const hw = 1.05, y0 = -4.3 + m.h, y1 = 3.7 + m.h;
    const Y = (y) => (mirror ? 2 * FLOOR - y : y);
    return [[px - tx * hw, Y(y1), pz - tz * hw], [px + tx * hw, Y(y1), pz + tz * hw], [px + tx * hw, Y(y0), pz + tz * hw], [px - tx * hw, Y(y0), pz - tz * hw]].map(raw ? (v) => v : proj);
  };
  const vis = mem.filter((m) => (Math.cos(m.a) * RING - CZ) > 3 && Math.abs(Math.sin(m.a) * RING / (Math.cos(m.a) * RING - CZ)) < 1.75).sort((a, b) => Math.abs(a.a) - Math.abs(b.a));

  // ---------------- the void: faint floor graticule (mirror floor), the clock on the floor
  const floorPt = (x, z) => proj([x, FLOOR, z]);
  c.save();
  c.lineWidth = 0.6;
  for (const r of [3, 6, 9, 12, 16, 22]) {
    c.beginPath();
    for (let k = 0; k <= 180; k++) {
      const a = -1.4 + (k / 180) * 2.8, [x, y, z] = floorPt(Math.sin(a) * r, Math.cos(a) * r);
      if (z < 0.3) continue;
      if (k) c.lineTo(x, y); else c.moveTo(x, y);
    }
    c.strokeStyle = rgba('red', r === RING - 1 ? 0.28 : 0.13); c.stroke();
  }
  for (let k = 0; k < 48; k++) {
    const a = (k / 48) * TAU; if (Math.cos(a) < 0.25) continue;
    const [x1, y1] = floorPt(Math.sin(a) * 3, Math.cos(a) * 3), [x2, y2] = floorPt(Math.sin(a) * (k % 4 ? 12 : 22), Math.cos(a) * (k % 4 ? 12 : 22));
    c.strokeStyle = rgba('red', k % 4 ? 0.06 : 0.14); c.beginPath(); c.moveTo(x1, y1); c.lineTo(x2, y2); c.stroke();
  }
  // clock hand toward the speaker
  const sm = mem.find((m) => m.speak);
  const [hx1, hy1] = floorPt(0, 0.8), [hx2, hy2] = floorPt(Math.sin(sm.a) * 9.2, Math.cos(sm.a) * 9.2);
  c.strokeStyle = rgba('red', 0.7); c.lineWidth = 1.4; c.beginPath(); c.moveTo(hx1, hy1); c.lineTo(hx2, hy2); c.stroke();
  // pooled red light on the floor under the speaker
  const [plx, ply] = floorPt(Math.sin(sm.a) * RING, Math.cos(sm.a) * RING);
  const g = c.createRadialGradient(plx, ply, 0, plx, ply, 260);
  g.addColorStop(0, rgba('red', 0.22)); g.addColorStop(0.4, rgba('red', 0.07)); g.addColorStop(1, rgba('red', 0));
  c.save(); c.translate(plx, ply); c.scale(1, 0.18); c.translate(-plx, -ply); c.fillStyle = g; c.fillRect(plx - 300, ply - 300, 600, 600); c.restore();
  c.restore();
  // horizon hairline
  const [, hzY] = proj([0, FLOOR, 1e4]);
  c.fillStyle = rgba('red', 0.18); c.fillRect(0, hzY, W, 0.6);

  const faceTex = (m, glow, hot) => {
    const fw = 100, fh = 300, S = 8, cv = document.createElement('canvas'); cv.width = fw * S; cv.height = fh * S;
    const c = cv.getContext('2d'); c.scale(S, S);
    const red = rgba('red', 0.35 + 0.65 * glow);
    c.shadowColor = rgba('red'); c.shadowBlur = hot ? 16 : 8 * glow;
    c.fillStyle = red; c.textAlign = 'center'; c.textBaseline = 'alphabetic';
    c.font = mono(700, 9); c.letterSpacing = '2px'; c.fillText('MEMBER', fw / 2, 34);
    c.letterSpacing = '0px';
    c.font = `600 86px ${SERIF}`;
    c.save(); c.translate(fw / 2, 118); c.scale(0.62, 1); c.fillText(String(m.id).padStart(2, '0'), 0, 0); c.lineWidth = 2; c.strokeStyle = red; c.strokeText(String(m.id).padStart(2, '0'), 0, 0); c.restore();
    c.fillRect(14, 132, fw - 28, 1.4);
    c.font = mono(700, 11.5); c.letterSpacing = '1.2px';
    c.fillText('SOUND', fw / 2, 156); c.fillText('ONLY', fw / 2, 171);
    c.letterSpacing = '0px';
    // face meter: chroma level
    c.shadowBlur = 0;
    const n = 14;
    for (let k = 0; k < n; k++) {
      const on = k / n < m.inten;
      c.fillStyle = rgba('red', on ? 0.3 + 0.6 * glow : 0.07);
      c.fillRect(36, 270 - k * 7, fw - 72, 4.5);
    }
    c.fillStyle = rgba('red', 0.5); c.font = mono(500, 7); c.fillText(NOTES[m.id - 1], fw / 2, 290);
    return cv;
  };
  // ---------------- monoliths
  const drawFace = (m, P, mirror, W3) => {
    const glow = 0.25 + 0.75 * m.inten, hot = m.speak;
    c.save();
    if (mirror) c.globalAlpha = 0.085;
    c.beginPath(); P.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); c.closePath();
    c.fillStyle = hot ? '#0d0504' : '#070504'; c.fill();
    // edge glow
    c.shadowColor = rgba('red', 1); c.shadowBlur = (6 + 22 * glow) * (hot ? 1.8 : 1);
    c.strokeStyle = rgba('red', 0.25 + 0.6 * glow); c.lineWidth = hot ? 2 : 1.1; c.stroke();
    c.shadowBlur = 0;
    // face content via affine map of the unit face (u 0..1 across, v 0..1 down)
    const tex = faceTex(m, glow, hot), n = 120;
    for (let k = 0; k < n; k++) {
      const u0 = k / n, u1 = (k + 1) / n;
      // perspective-correct: interpolate in 3D, then project
      const at = (u, top) => { const A = W3[top ? 0 : 3], B = W3[top ? 1 : 2]; return proj([A[0] + (B[0] - A[0]) * u, A[1] + (B[1] - A[1]) * u, A[2] + (B[2] - A[2]) * u]); };
      const t0 = at(u0, 1), b0 = at(u0, 0), t1 = at(u1, 1);
      const x0 = t0[0], x1 = t1[0], yt = t0[1], yb = b0[1];
      if (yb > yt) c.drawImage(tex, u0 * tex.width, 0, tex.width / n, tex.height, x0, yt, x1 - x0 + 0.3, yb - yt);
      else { c.save(); c.translate(0, yt); c.scale(1, -1); c.drawImage(tex, u0 * tex.width, 0, tex.width / n, tex.height, x0, 0, x1 - x0 + 0.3, yt - yb); c.restore(); }
    }
    c.restore();
  };
  for (const m of vis) drawFace(m, corners(m, true), true, corners(m, true, true));
  for (const m of vis) drawFace(m, corners(m, false), false, corners(m, false, true));
  c.setTransform(2, 0, 0, 2, 0, 0);

  // ---------------- sparse terminal
  const rc = rgba('red', 0.8);
  // top-left: committee header
  evaLabel(c, 34, 62, 'closed session // 07:14:22', '人類補完委員会  非公開審議', { color: rgba('red', 0.85), size: 0.9 });
  c.fillStyle = rgba('red', 0.5); c.fillRect(34, 88, 230, 1);
  text(c, 'VOICE CHANNELS 12 / ENCRYPTED', 34, 102, { size: 8, color: rgba('red', 0.55) });
  // top-right: speaker callout
  const sx = 1246;
  text(c, 'MEMBER 07', sx, 62, { weight: 700, size: 13, color: rgba('red'), align: 'right', track: 3, glow: 8 });
  c.font = jp(13, 700, false); c.fillStyle = rgba('red', 0.9); c.textAlign = 'right'; c.fillText('発言中  ／  SPEAKING', sx, 82); c.textAlign = 'left';
  // voice scope
  c.save(); c.beginPath();
  for (let i = 0; i <= 200; i++) {
    const u = i / 200, env = Math.sin(u * Math.PI);
    const v = (Math.sin(u * 90) * 0.6 + (fbm(u * 30, 4) - 0.5)) * env;
    const x = sx - 200 + u * 200, y = 106 - v * 12;
    if (i) c.lineTo(x, y); else c.moveTo(x, y);
  }
  c.strokeStyle = rgba('red', 0.9); c.lineWidth = 1; c.shadowColor = rgba('red'); c.shadowBlur = 5; c.stroke(); c.restore();
  c.fillStyle = rgba('red', 0.35); c.fillRect(sx - 200, 124, 200, 0.8);
  // leader line from callout to the speaker's top
  const sp = corners(sm, false);
  const tx = (sp[0][0] + sp[1][0]) / 2, ty = sp[0][1];
  c.strokeStyle = rgba('red', 0.5); c.lineWidth = 0.8;
  c.beginPath(); c.moveTo(sx - 200, 124); c.lineTo(sx - 212, 136); c.lineTo(tx + 12, 136); c.lineTo(tx, 148); c.lineTo(tx, ty - 8); c.stroke();
  brackets(c, sp[0][0] - 10, sp[0][1] - 10, sp[1][0] - sp[0][0] + 20, sp[3][1] - sp[0][1] + 20, 10, rgba('red', 0.8), 1);

  // bottom-left: roster
  const ry = 640;
  text(c, 'COUNCIL ROSTER // 名簿', 34, ry, { weight: 700, size: 9, color: rc, track: 2 });
  for (let i = 0; i < 12; i++) {
    const x = 34 + (i % 6) * 56, y = ry + 16 + Math.floor(i / 6) * 40;
    const hot = i + 1 === SPEAK;
    c.fillStyle = hot ? rgba('red', 0.9) : rgba('red', 0.1);
    chamferPath(c, x, y, 50, 32, [0, 6, 0, 0]); c.fill();
    c.strokeStyle = rgba('red', 0.5); c.lineWidth = 0.7; c.stroke();
    text(c, String(i + 1).padStart(2, '0'), x + 5, y + 14, { weight: 700, size: 10, color: hot ? rgba('ink') : rgba('red', 0.8) });
    text(c, NOTES[i], x + 45, y + 14, { size: 8, color: hot ? rgba('ink') : rgba('red', 0.5), align: 'right' });
    c.fillStyle = hot ? rgba('ink') : rgba('red', 0.55); c.fillRect(x + 5, y + 22, 40 * chroma[i], 3);
  }
  // bottom-right: minutes typing out
  const minutes = [
    ['07', 'THE THIRD CHILD HAS BEEN DEPLOYED.'], ['04', 'THE SCENARIO DEVIATES FROM THE SCROLLS.'], ['07', 'THE ANGEL APPROACHES AS FORETOLD.'],
    ['11', 'NERV WILL ANSWER FOR THE COST.'], ['07', '予定通りだ。  ALL IS ACCORDING TO THE SCENARIO_'],
  ];
  const mx = 846;
  text(c, 'MINUTES // 議事録', mx, ry, { weight: 700, size: 9, color: rc, track: 2 });
  minutes.forEach(([m, s], i) => {
    const y = ry + 22 + i * 16.5, last = i === minutes.length - 1;
    text(c, `[${m}]`, mx, y, { weight: 700, size: 9, color: rgba('red', last ? 1 : 0.55) });
    c.font = /[　-鿿]/.test(s) ? jp(10, 600, false) : mono(500, 9); c.letterSpacing = '0.8px';
    c.fillStyle = rgba('red', last ? 0.95 : 0.4 + 0.1 * i); c.fillText(s, mx + 34, y); c.letterSpacing = '0px';
  });
  // chromagram voice print
  const vx = 34, vy = 742;
  for (let t = 0; t < 110; t++) for (let p = 0; p < 12; p++) {
    const v = clamp(chroma[p] * (0.55 + 0.6 * fbm(t * 0.13 + p * 3.1, 21)) - 0.15);
    c.fillStyle = rgba('red', 0.05 + 0.7 * v * v); c.fillRect(vx + t * 3.1, vy + p * 2.6, 2.6, 2.1);
  }
  text(c, 'VOICE PRINT // 声紋  12 PC × 110', vx, vy + 44, { size: 7.5, color: rgba('red', 0.5) });
  // frame corners
  brackets(c, 16, 40, W - 32, H - 56, 22, rgba('red', 0.55), 1);
  text(c, 'SOUND ONLY', W / 2, 784, { weight: 700, size: 9, color: rgba('red', 0.5), align: 'center', track: 6 });
  return { threshold: 0.45, bloom: 1.1, vignette: 0.5, ca: 1 };
});
